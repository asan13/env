package SO::BulkGate::Router::Replace;

use common::sense;
use Data::Dumper;



use SO::BulkGate::Router::Rule;

sub new {
    my $class = shift;

    bless my $self = {}, $class;

}



sub apply {
    my ($self, $rules, $replaces) = @_;


    my %replaces = map {
            $_->{name} => {r => SO::BulkGate::Router::Rule::Replace->new($_)}
        } @$replaces 
    ;

    my $rc = 'SO::BulkGate::Router::Rule::Replace';
    foreach my $rule ( @$rules ) {

        foreach my $rname ( keys %replaces ) {

            my $repl = $replaces{$rname}{r};
            
            my $res = eval { $repl->match_rule($rule) };
            if ($@) {
                die "$@", Dumper "rname: $rname", $rule;
            }

            next unless $res;

            my $sub_repl = $repl->get_action($rule);

            if ($res == $rc->MATCH_EXCLUSIVE) {
                delete $replaces{$rname};
            }
            else {
                $replaces{$rname}{i}{$rule->name}++;
            }

            $rule->add_replace($rname, $sub_repl);

        }

    }

    return grep !$_->{i}, values %replaces;
}



1;


