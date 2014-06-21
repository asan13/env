package SO::BulkGate::Interface::KievStar;

use strict;
use warnings;
use 5.010;

use parent 'SO::BulkGate::Interface::Base';


use Data::Dumper;
use Carp;
use MIME::Base64;
use Encode;
use URI::Escape;
use XML::Fast;

use SO::HTTP::Request;
use SO::BulkGate::Constants qw/:status/;
use SO::BulkGate::LogWrap;

use Class::XSAccessor 
  getters => {
    uaks_xid  => 'uaks_xid',
    uaks_paid => 'uaks_paid',
    user      => 'user',
    pass      => 'pass',
    msg_part  => 'msg_part',
  };



sub new {
  my __PACKAGE__ $class = shift;
  my $args  = ref $_[0] ? $_[0] : {@_};

  my $self = $class->SUPER::new($args);
  $self->{uaks_xid}  = $args->{uaks_xid};
  $self->{uaks_paid} = $args->{uaks_paid};

  $self->_set_auth($args);

  return $self;
}


sub _set_auth {
  my ($self, $args) = (shift, shift);

  my ($user, $pass, $url, $proto);
  WARN "\e[38;5;135mKievStar\e[0m", $self;
  if ( $self->url =~ m{^([^:]+):([^@]+)\@(.+)$} ) {
    ($user, $pass, $url) = ($1, $2, $3);
    ($proto) = $url =~ /^(https?):/; 
    $url = (($proto ||= 'http') . '://') . $url unless $proto;
    $self->url($url);
  }
  $user = $args->{user} if $args->{user};
  $pass = $args->{pass} if $args->{pass};

  unless ($user && $pass) {
    croak q[KievStar protocol uses basic autorization. ]
        . q[Required parameters 'user' and 'pass']
    ;
  }

  $self->{user} = $user;
  $self->{pass} = $pass;
  $self->{auth} = 'Basic ' . MIME::Base64::encode("$user:$pass", '');

  $self->{msg_part} = 0;

  $self->{headers} = {
    'content-type'  => 'text/xml',
    'authorization' => $self->{auth},
  };

}


sub sms_make_request {
  my ($self, $ctx, $rule) = @_;
  
  my $mid  = $ctx->{id} . '.1' . $rule->{uaks_xid};
  my $paid = $rule->{uaks_paid};
  my $text = Encode::encode('utf8', xml_escape( $ctx->{txt} ));

  my $xml = <<__XML__;
<?xml version="1.0" encoding="UTF-8"?>
<message mid="$mid" paid="$paid" bearer="SMS">
  <sn>$ctx->{from}</sn>
  <sin>$ctx->{to}</sin>
  <body content-type="text/plain">
  $text
  </body>
</message>
__XML__

  $ctx->logger->info("\e[38;5;58msms_make_request:\n$xml\e[0m");

  return SO::HTTP::Request->new(
    url     => $self->url,
    body    => $xml, 
    headers => $self->{headers},
    method  => 'POST'
  );
}


sub sms_parse_reply {
  my ($self, $body, $ctx) = @_;

  if ( $body =~ /Accepted/ ) {
    $ctx->st_delivered();
    $ctx->logger->debug("sms_parse_reply (KievStar) OK\n$body");
  }
  elsif ( $body =~ 'Rejected' ) {
    $ctx->st_rejected();
    my ($error) = $body =~ /error="([^"]+)"/;
    $ctx->logger->error("sms_parse_reply: $error\n$body");
  }
  else {
    croak "bad response from kyivstar:\n" . Dumper($body);
  }
}


sub process_dlr {
  my ($self, $answer, $ctx) = @_;

  my $log = $self->log;
  $log->info("posted: body=$answer");

  unless ($answer =~ /mid="[^"]+"/) {
    $log->error(qq[invalid dlr report, cannot find mid="xxx": $answer]);
    return;
  }

  my $status = $answer =~ /Delivered/ ? ST_DELIVERED : ST_REJECTED;
  my $descr;
  if ($status == ST_DELIVERED) {
    $descr = 'Delivered';
  }
  else {
    ($descr) = $answer =~ /error\s+=\+"([^"])/;
  }

  $log->info("[msgid: $ctx->{id}] registering delivery: "
           . ($status == ST_DELIVERED ? 'ST_DELIVERED' : 'ST_REJECTED')
           . ", status: $descr, gate: $ctx->{where}"
  );

  return $status;
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

1;
