#!/usr/bin/perl

use 5.010;
use strict;
use warnings;
use utf8;

use Data::Dumper;
use AnyEvent;
use JSON;
use Plack::Request;
use Encode;

use FindBin qw($Bin);

use SO::BulkGate::Context;
use SO::Loader::Facility;

########################
#  Setup

my $JSON = JSON->new->allow_blessed->convert_blessed;

SO::Loader::Facility->init(
  config => [[{
    log => {
      sys_logger => 's.bulk_gate.psgi',
      biz_logger => 'b.bulk_gate.psgi',
    },
  }]],
  facilities => [ qw( Qu ) ],
);

my $logger = SO::Log::Facility->get_sys_logger;
$logger->info ("Starting ".__FILE__."...");
END { $logger->info ("Finished ".__FILE__); };

my %queue;
$queue{sms} = SO::Qu::Facility->get_async_queue('bulk_gate_sms');
$queue{dlr} = SO::Qu::Facility->get_async_queue('bulk_gate_dlr');

$logger->info (__FILE__." up and running");

# /Setup
########################


sub error {
  $logger->warn( shift );
  return [ 500, [], [] ];
};

sub done {
  $logger->debug("request ok");
  return [ 200, [], \@_ ];
};


sub enqueue {
  my $type = shift;
  my $data = shift;

  $data->{type} = $type;

  $logger->debug( "Enqueue $type" );

  return sub {
    my $responder = shift;

    $queue{sms}->enqueue(
      message => $data,
      on_error => sub { $responder->(error( shift )) },
      on_done => sub { $responder->(done( )) },
    );
  };
};

my %k_status = (
  1 => 0,
  2 => -1,
  4 => 1,
  8 => 1,
  16 => -3,
);

sub recv_dlr {
    my ($data, $r) = (shift, shift);

    if ( $r->method eq 'POST' ) {
        my $body = '';
        my ($off, $len) = (0, $r->content_length);
        my $rb;
        my $b = $r->body;
        while ( $rb = $b->read($body, 2048, $off) ) {
            $len -= $rb;
            $off += $rb;
            last unless $len > 0;
        }

        unless (defined $rb) {
            return [400, [], []];
        }

        $data->{body} = $body;
    }
    elsif ($r->method eq 'GET') {
        $data->{status} = $k_status{$data->{status}};
        $logger->error('Invalid status for ' . Dumper $data)
            unless defined $data->{status};
    }

    enqueue( "dlr", $data );
}

sub recv_sms {
    my $raw = shift;

    $logger->trace ("Raw data: ", $raw);

    my ($msg, $leftover);
    eval { ($msg, $leftover) = SO::BulkGate::Context->filter_input($raw) };
    if ( $msg ) {
        $logger->error("Extra params in call to bulkgate: ", $leftover)
            if ($leftover);
        $logger->trace("Filtered data: ", $msg->TO_JSON);
        return enqueue("sms", $msg->TO_JSON);
    } 
    else {
        $logger->debug("Bad message: $@");
        return [ 400, [ ], [ "Bad sms format" ]];
    }
}

my %stat;
my $stat_cache;
sub show_stat {
  my $tm;
  $stat_cache ||= do {
    $tm = AE::timer 1, undef, sub { undef $stat_cache };
    $JSON->encode(\%stat);
  };
  return [ 200, [ 'Content-Type' => 'application/json' ], [ $stat_cache ]];
};

my %route = (
  'mt.cgi' =>   \&recv_sms,
  'dlr.cgi' =>  \&recv_dlr,
#  'stat.cgi' => \&show_stat,
);

my $route_re = join "|", map { quotemeta } reverse sort keys %route;
$route_re = qr/($route_re)/o;

sub route {
  my $req = Plack::Request->new(shift);

  my $path = $req->path_info;

  my $data = { map { decode_utf8($_) } %{ $req->parameters } };

  $path =~ $route_re or return [ 404, [], [] ];
  return $route{$1}->($data, $req);
}

my $app = \&route;

