#!/usr/bin/perl
#
#

use common::sense;
use Data::Dumper;

use Encode qw/decode/;
use URL::Encode::XS qw/url_decode/;
use String::CRC32;
use Plack::Request;
use AnyEvent;
use Getopt::Long;

use SO::Config;
use SO::Qu::Facility;
use SO::Loader::Facility;

sub _DEBUG() { 1 };

sub SYS_LOGGER() { 's.bulk_gate.front' }
sub BIZ_LOGGER() { 'b.bulk_gate.front' }


use Redis;


my (%QUEUES, $NUMBER_QUEUES);
my $LOGGER; 


sub inner_app {

    config();

    eval q#
    sub inner_app {
        my $r = Plack::Request->new(shift);

        if ($r->path =~ m!^/(mt|dlr)!) {
            return process_request($r, $1);
        }
        else {
            return [400, [], []];
        }
    }
    #;
    if ($@) {
        $LOGGER->error($@);
        die $@ if $@;
    }

    &inner_app;
}

sub app {
    inner_app(@_);    
}

\&app;




sub process_request {
    my ($req, $type) = (shift, shift);


    return sub {
        my $respond = shift;

        eval {

            my $data;
            if ( $req->method eq 'GET' || 
                 $req->content_type eq 'application/x-www-form-urlencoded'
            ) {
                my $params = $req->parameters;
                foreach ( keys %$params ) {
                    $data->{$_} = $params->{$_};
                }
                die 'Invalid request' unless keys %$data;
            }
            else {
                $data->{body} = $req->content
                    or die 'Invalid request';

                $data->{body} = url_decode( $data->{body} );
            }



            foreach (values %$data) {
                $_ = decode('utf8', $_);
            }

            $data->{type} = $type eq 'mt' ? 'sms' : 'dlr'; 

            my $key = get_ident($data) % $NUMBER_QUEUES + 1 || 1;
            my $queue = $QUEUES{$key};

            $LOGGER->debug(
                "Incoming request [$data->{type}]: queue $key", $data
            );

            $queue->enqueue( message  => $data,
                             on_done  => sub { $respond->([200, [], []]) },
                             on_error => sub { 
                                               $LOGGER->error(@_);
                                               $respond->([500, [], []]);
                                         },
                           );
            
        };

        if ($@) {
            warn "ERROR: $@";
            $LOGGER->error("$@: " . $req->uri);
            $respond->([400, [], ['Invalid request']]);
            return;
        }
        

    };
}

sub get_ident {
    my $data = shift;
    
    my $ident = $data->{to} || $data->{ident};

    unless ($ident) {
        if ($data->{body}) {
            ($ident) = $data->{body} =~ /mid="([^"]+)/; 
        }
    }

    $ident = int $ident;
    return $ident if $ident >= 1;
    
    if ( length $ident ) {
        return crc32($ident); 
    }

    return 42;
}

sub queue_name {
    my ($name, $num) = @_;
    return "${name}_${num}_";
}

sub config {

    my $n_queues;
    GetOptions(
        'queues|n=i' => \$n_queues, 
    );

    my $conf = SO::Config->load( qw!bulk_gate/conf qu! );
    my $qu_name   = $conf->{bulk_gate}{sms_queue};
    my $qu_bulk   = $conf->{&SO::Qu::Facility::CONFIG_KEY}{queues}{$qu_name};
    $n_queues ||= $conf->{daemon}{workers_number};


    my $queues;
    foreach (1..$n_queues) {
        $queues->{ queue_name($qu_name, $_) } = { %$qu_bulk };
    }

    SO::Loader::Facility->init(
        facilities => [ qw/Qu/ ],
        config => [[{
            log => {
                sys_logger => SYS_LOGGER,
                biz_logger => BIZ_LOGGER,
#                redirect_stderr => 0,
            },

            qu => { queues => $queues },
        }]]
    );

    $LOGGER = SO::Log::Facility->get_sys_logger();

    foreach (1..$n_queues) {
        $QUEUES{$_} = SO::Qu::Facility->get_async_queue( 
            queue_name($qu_name, $_)
        );
    }

    $NUMBER_QUEUES = $n_queues;
    
}






