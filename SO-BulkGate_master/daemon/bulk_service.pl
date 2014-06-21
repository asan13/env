#!/usr/bin/perl
#
#

use common::sense;
use Data::Dumper;

use Getopt::Long;

my %args;
GetOptions(
    'help|h' => \$args{help},
);


my $serv = BulkService->new(%args);

$serv->run();




package BulkService;

use Data::Dumper;
use JSON::XS;
use POSIX qw/setsid/;
use HTTP::Parser::XS 'parse_http_request';
use Plack::Request;
use AnyEvent;
use AnyEvent::Socket;

use SO::Config::Facility;
use SO::Log::Facility;
use SO::BulkGate::Config;
use SO::BulkGate::Ctx;


BEGIN {
    for my $method ( qw/info warn error/ ) {
        my $level = uc($method) . ': ';
        *{$method} = sub { 
            my $self = shift;
            say $level, join ' ', @_;
            $self->log->$method(@_);
        };
    }
}

use Class::XSAccessor
    accessors => [ 
        qw/conf log bulk_pid_file pid_file notify_name port json
           notify_name notify_period
        / 
    ],
;


sub new {
    bless my $self = {}, shift;

    $self->init(@_);
    $self;
}

sub init {
    my ($self) = (shift);

    SO::Config::Facility->init( qw!sys db log bulk_gate/conf! );
    my $config = SO::Config::Facility->get_config;
    $self->pid_file( $config->{bulk_gate}{service_pid_file} 
                    || '/var/run/bulk_gate/service.pid' );


    $self->daemon();

    SO::Log::Facility->init();
    $self->log( SO::Log::Facility->get_sys_logger() );
    $self->conf( 
        SO::BulkGate::Config->init( config => $config )
    );

    $self->bulk_pid_file( $config->{daemon}{pid_file} )
        or die 'bulkgate daemon pid file not found';


    unless ( -f $self->bulk_pid_file ) {
        $self->warn("Can't read bulkgate pid file '$self->{bulk_pid_file}'");
    }

    $self->port( $config->{bulk_gate}{service_port} || 5001 ); 

    $self->notify_name( 
        $config->{bulk_gate}{service}{notify_name} || 'bulk_reload'
    ); 
    $self->notify_period( 3
#        $config->{bulk_gate}{service}{notify_period} || 10
    ); 

    my $dbh = $self->conf->get_dbh;
    $dbh->do('LISTEN ' . $self->notify_name . ';');

    $self->json( JSON::XS->new->allow_unknown );

}

sub daemon {

    my $pid = fork && exit;
    die "fork: $!" unless defined $pid;

    setsid or die "setsid: $!";

    open STDIN,  '<', '/dev/null' or die "reopen: $!"; 
    open STDOUT, '>', '/dev/null' or die "reopen: $!"; 
#    open STDERR, '>', '/dev/null' or die "reopen: $!"; 
}

sub run {

    my $self = shift;

    my $cv = AE::cv;

    tcp_server undef, $self->port, $self->http_server;

    my $notify_w = AE::timer 5, $self->notify_period, 
        sub {
            $self->read_notify;
        };

    my $hup_w = AE::signal HUP => 
        sub {
            $self->reload;
        };

    my $term_w = AE::signal TERM => sub { $cv->send };

    $cv->recv;
}


sub read_notify {
    my $self = shift;

    eval {
        my $dbh = $self->conf->get_dbh;

        if ($dbh->pg_notifies) {
            $self->notify_bulkgate;
            $self->conf->setup_data();
        }
    };
    if ($@) {
        $self->error("$@");
    }
}


sub notify_bulkgate {
    my $self = shift;

    if ( my $bulk_pid = $self->get_bulk_pid ) {
        $self->info("send $self->{HUP} to bulkgate [$bulk_pid]");
            
        my $res = kill $self->HUP => $bulk_pid;
        unless ($res) {
            $self->error("notify bulkgate: $!");
        }
    }
}


sub get_bulk_pid {
    my $self = shift;

    my $pid;
    eval {
        open my $fh, '<', $self->bulk_pid_file 
            or die "open bulk pid file: $!";

        sysread $fh, $pid, 5 or die "read bulk pid: $!";
        $pid = int $pid;
    };
    if ($@) {
        $self->error($@);
    }

    return $pid;
}


sub http_server {
    my $self = shift;

    return sub {
        my ($fh, $host, $port) = @_;

        $self->info("request from $host:$port");

        $fh->blocking(0);

        my ($w, $buf);
        $w = AE::io $fh, 0, sub {

            my $br = sysread $fh, $buf, 1024, length $buf;
            unless (defined $br) {
                return if Errno::EAGAIN == $! || Errno::EWOULDBLOCK == $!;
            }

            unless ($br) {
                undef $w;
                $self->error("$host:$port read: $!");
                return;
            }

            return unless $buf =~ /\r?\n\r?\n$/;

            my %env;
            my $res = parse_http_request($buf, \%env);

            unless ($res >= 0) {
                undef $w;
                $self->error("broken request: $buf");
                return;
            }

            undef $w;

            my $r = Plack::Request->new(\%env);

            $self->dispatch($fh, $r);

        }
    };
}

sub dispatch {
    my ($self, $fh, $req) = @_;

    my $resp = $req->new_response;
    $resp->content_type('application/json');
    my $body = '';

    if ($req->path eq '/rules') {

        my $rules = $self->get_rules($req->parameters);

        $body = $self->json->encode({rules => $rules});
        $resp->status(200);
    }
    else {
        $resp->status(400);
        $body = $self->json->encode({error => 'Invalid request'});
    }

    $resp->content_length(length $body);

    my $answer = 'HTTP/1.0 ' . $resp->status . " OK\r\n"
               . $resp->headers->as_string . "\r\n"
               . $body
    ;

    say $answer;

    my $w;
    $w = AE::io $fh, 1, sub {
        my $bw = syswrite $fh, $answer;
        return if !defined $bw 
                && ( Errno::EAGAIN == $! || Errno::EWOULDBLOCK == $! );

        unless ($bw) {
            $self->error("write response: $!");
            undef $w;
            $fh->close;
            return;
        }

        if ($bw < length $answer) {
            substr $answer, 0, $bw, '';
            return;
        }

        undef $w;
        $fh->close;
    };
}


sub get_rules {
    my ($self, $params) = (shift, shift);

    my $args;
    foreach my $key ( qw/mccmnc cn from partner/ ) {
        next unless defined $params->{$key};
        $args->{$key} = $params->{$key};
    }
    unless ($args) {
        return [];
    }

    my $ctx = SO::BulkGate::Ctx->new($args);
    my @rules = map { {%$_} } $self->conf->rules->search($ctx);
    return [ @rules ]
}


1;


