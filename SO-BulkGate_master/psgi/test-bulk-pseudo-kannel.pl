#!/usr/bin/perl -w

use strict;
use Plack::Request;
use AnyEvent;
use AnyEvent::HTTP;
use JSON;
use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init({
  level => $INFO,
#  category => __PACKAGE__,
  layout => '%d [%P] PSEUDO-KANNEL %p: %m{chomp}%n',
});
my $logger = Log::Log4perl->get_logger("");

# Statistics

my %stat;
{
  my $timer = AnyEvent->timer( after => 1, interval => 1, cb => \&show_stat);
  sub show_stat {
    $logger->info( "Stats: ".encode_json (\%stat)."\n" )
      if scalar keys %stat;
    %stat = ();
  };

  END { undef $timer}; # keep timer in scope forever
};

# Random status sender
# 1, 2, and 16 are final
my @st = (1,1,2,16,8,8,8,8,4,4,4,4);

$AnyEvent::HTTP::MAX_PER_HOST = 256; # don't limit connections
sub rand_status {
  my $where = shift;
  my $count = shift || 0;
  my $timer;

  if (!$count) { $stat{sms}++ };

  $timer = AnyEvent->timer( after => rand(), cb => sub {
    my $url = $where;

    $url =~ s/%d/$st[ rand() * @st ]/ge;
    $logger->debug( "Send random status to $url [$count]...\n" );
    $stat{dlr}++;
    http_get $url, sub {
      my ($body, $hdr) = @_;
      $hdr->{Status} =~ /^2/ ? $stat{dlr_ok}++ : $stat{dlr_err}++;
      $logger->debug( " ... $url [$count]: $hdr->{Status} $hdr->{Reason}\n" );
    };
    undef $timer;

    if (++$count < 5) {
      rand_status( $where, $count )
    };
  });
};

$logger->info("$0 ready...");

my $app = sub {
  my $req = Plack::Request->new(shift);
  my $data = $req->parameters;

  my $dlurl = $data->{'dlr-url'};
  if (!$dlurl) {
    return [ 400, [], [] ];
  };
  if ($data->{smsc}) {
    $stat{"smsc=$data->{smsc}"}++;
  };

  rand_status($data->{'dlr-url'});
  return [ 200, [], [] ];
};

