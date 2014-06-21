package SO::BulkGate::Interface::Base;

use common::sense;
use Carp;


our $VERSION = 0.113;




sub new {
    bless {}, shift;
}

sub sms_make_request { 1 }

sub sms_parse_reply { 1 }

sub process_dlr { 1 } 


sub TO_JSON {
  return { %{+shift} };
}

1;
