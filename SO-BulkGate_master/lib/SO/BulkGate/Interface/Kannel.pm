
package SO::BulkGate::Interface::Kannel;

use common::sense;
use Data::Dumper;
use parent 'SO::BulkGate::Interface::Base';

use URL::Encode::XS qw/url_encode/;
use SO::Text;

use Class::XSAccessor 
    getters => [ qw/dlr_url/ ],
;



sub new {
    my $class = shift;
    my $args  = ref $_[0] ? {%${[0]}} : {@_};

    my $self = $class->SUPER::new($args);
    
    $self->{dlr_url} = $args->{dlr_url};

    $self;
}


my %GATE_URL;

sub make_request {
    my ($self, $ctx) = (shift, shift);

    my $gate = $ctx->gate;

    my $url;
    unless ( $url = $GATE_URL{$gate->name} ) {
        $url = $gate->url;
        $url .= '?' unless $url =~ /\?/;
        $url .= '&' unless $url =~ /(?:\?|&)\z/;
        $url .= 'dlr-mask=31&';

        my $params = $gate->params;
        $url .= join '&', map {+"$_=" . url_encode($params->{$_})} keys %$params;
        $url .= '&';

        $GATE_URL{$gate->name} = $url;
    }

    $url .= 'dlr-url=' .  url_encode( $self->dlr_url 
                                    . '&id=' . $ctx->id 
                                    . '&tid=' . $ctx->tid
                          ) . '&';

    my $params = $ctx->params;
    if ( my $text = SO::Text->normalize_latin1_7b($params->{text}) ) {
        $params->{text}   = $text;
        $params->{coding} = 0;
    }
    elsif (!$gate->encoding) {
        $params->{text}   = Encode::encode('UCS-2', $params->{text});
        $params->{coding} = 2; 
    } 
    else {
        $params->{text}   = Encode::encode($gate->encoding, $params->{text});
        $params->{coding} = 1; 
    }

    $url .= join '&', map {+ "$_=" . url_encode($params->{$_})} keys %$params;

    return [GET => $url];    

}

sub on_response {
    return sub {
    }
}


sub process_dlr {
    my ($self, $data) = (shift, shift);

    return {status => $self->convert_status($data->{status})};
}

my %KANNEL_STATUS = (
    1  =>  0,
    2  => -1,
    4  =>  1,
    8  =>  1,
    16 => -3,
);

sub convert_status {
    $KANNEL_STATUS{$_[1]};
}


1;
