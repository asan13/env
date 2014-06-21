package SO::BulkGate::Router::Gates;

use common::sense;
use Data::Dumper;


use SO::BulkGate::Router::Gate;

use Class::XSAccessor 
    getters => [ qw/gates/ ],
;


sub new {
    my $class = shift;

    bless my $self = {}, $class;
}


sub setup {
    my ($self, $data, $reload) = @_;


    if ($reload) {
        $self->{gates} = { 
            map { $_->{name} =>SO::BulkGate::Router::Gate->new(%$_) } @$data 
        };
    }
    else {
        foreach my $gate ( @$data ) {
            $self->set_gate($gate);
        }
    }

}


sub set_gate {
    my ($self, $data) = (shift, shift);

    my $gate = SO::BulkGate::Router::Gate->new($data);
    $self->{gates}{$gate->name} = $gate;
}

sub get_gate {
    $_[0]->{gates}{$_[1]};
}


1;
