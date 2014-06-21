package SO::BulkGate::Interface::Redirect;

use common::sense;
use Data::Dumper;
use parent 'SO::BulkGate::Interface::Base';

sub new {
    my $class = shift;
    my $args  = ref $_[0] ? {%$_[0]}} : {@_};

    my $self = $class->SUPER::new($args);

    $self->{url} = $args->{url};
    $self->{url} .= '?' unless $self->{url} =~ /\?/;
    $self->{url} .= '&' unless $self->{url} =~ /(?:\?|&)\z/;

    $self;

}

sub make_request {
    my ($self, $ctx) = (shift, shift);

}


1;
