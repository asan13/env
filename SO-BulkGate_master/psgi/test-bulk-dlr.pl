#!/usr/bin/perl -w

use strict;

use Plack::Request;
use AnyEvent;
use JSON;
use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init({
  level => $INFO,
#  category => __PACKAGE__,
  layout => '%d [%P] PSEUDO-DLR %p: %m{chomp}%n',
});
my $logger = Log::Log4perl->get_logger("");

my $timer = AnyEvent->timer ( after => 1, interval => 1, cb => \&show_stat );

my %longstat;
my %stat;
sub show_stat {
  return unless %stat;

  my $total;
  foreach (keys %stat) {
    $total += $stat{$_};
    $longstat{final} += $stat{$_} if $_ <= 0;
    $longstat{sent} += $stat{$_} if $_ == 1;
  };
  $stat{TOTAL} = $total;

  $logger->info( "Stats: ".encode_json (\%stat)."\n" );
  %stat = ();
};
END { undef $timer }; # keep in scope

my $fin_timer = AnyEvent->timer (after => 5, interval => 5, cb => sub {
  %longstat or return;
  $logger->info("#### Average delivery rate: "
      .($longstat{final} / 5) ."/" .($longstat{sent}  / 5)
    );
  %longstat = ();
});
END { undef $fin_timer }; # keep in scope

$logger->info("$0 ready...");
my $app = sub {
  my $env = shift;
#  $logger->debug( "Params: ".encode_json($data)."\n" );

  $env->{REQUEST_URI} =~ /status=([^&]+)/
    and $stat{$1}++;
  return [ 200, [ 'Content-Type' => 'text/plain' ], ["Dlr OK\n"] ];
};

