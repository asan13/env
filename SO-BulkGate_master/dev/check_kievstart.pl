#!/usr/bin/perl 
#
#

use common::sense;

use Data::Dumper;
use POSIX qw/strftime/;
use MIME::Base64;
use Getopt::Long;
use AnyEvent::HTTP;

my ($sms_url, $dlr_url) = qw[
    http://sdp1.cpa.net.ua:8080/cpa2/receiver
    https://bulk.sms-online.com/kievstar/ua/dlr
];
my ($user, $pass) = qw/smsonline2 sDf89xA/;



my ($phone, $params, $uaks, $dlr);
{ 
    local $SIG{__WARN__} = sub { die "@_" };

    GetOptions(
        'phone=s'        => \$phone,
        'params|p=s%{,}' => sub { 
                                push @{$params->{$_[1]}}, map {split /,/} $_[2];
                            },
        'uaks|u=s'       => \$uaks,
        'dlr|d'          => \$dlr,
    );
}


my ($url, $headers, $body) = !$dlr ? sms_request() : dlr_request();

say "\e[38;5;42m\nurl: $url\n", Dumper($headers, $body), "\e[0m\n";

my $cv = AE::cv;

http_request POST => $url, headers => $headers, body => $body,  
                           Redirect => 1,
    sub {
        my $C = "\e[38;5;${_}m" for ($_[0] ? 42 : 197);
        say $C, Dumper \@_, "\e[0m";
        $cv->send;
    }
;


$cv->recv;


sub sms_request {
    die 'phone required' unless $phone;

    $params->{text} = xml_escape($params->{text} || 'Test KievStarrr');
    $params->{from} ||= '2442';
    my $xid  = $uaks && $uaks eq '2000' ? '12' : '15';
    my $mid  = sprintf '1313%d%d.1.%s', time, int rand 10_000, $xid; 
    my $paid = 2500;

    my $body = <<__XML__;
<?xml version="1.0" encoding="UTF-8"?>
<message mid="$mid" paid="$paid" bearer="SMS">
    <sn>$params->{from}</sn>
    <sin>$phone->{to}</sin>
    <body content-type="text/plain">
    $params->{text}
    </body>
</message>
__XML__

    my $headers = {
        'content-type'  => 'text/xml',
        'authorization' => 'Basic ' . MIME::Base64::encode("$user:$pass", ''),
    };

    return ($sms_url, $headers, $body); 
}


sub dlr_request {
    my $mid  = '2323' . time() . int( rand 10_000 ) . '.1.13';
    my $date = strftime '%a, %d %b %Y %H:%M:%S GMT', localtime;
    my $body = <<__XML__;
<?xml version="1.0" encoding="UTF-8"?>
<message mid="$mid" nodeId="0">
    <service>delivery-report</service>
    <status date = "$date" >Delivered</status>
</message>
__XML__

    return ($dlr_url, {'content-type' => 'text/xml'}, $body);
}


sub xml_escape {
  my $str = shift;
  $str =~ s/&/&amp;/g;
  $str =~ s/</&lt;/g;
  $str =~ s/>/&gt;/g;
  $str =~ s/"/&quot;/g;
  $str =~ s/'/&#39;/g;
  return $str;
}





