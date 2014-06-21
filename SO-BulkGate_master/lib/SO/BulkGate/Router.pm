package SO::BulkGate::Router;


use common::sense;
use Data::Dumper;

use Class::XSAccessor;


use SO::BulkGate::Config;
use SO::BulkGate::LogWrap;


use Class::XSAccessor
    accessors => {
        ( map {$_ => $_}

          qw/gates rules/
        ),
    }
;



sub new {
    my $class = shift;
    my %args  = @_;

    bless my $self = {}, $class;

    $self->gates( $args{gates} ) or die 'gates require';
    $self->rules( $args{rules} ) or die 'rules require';

    $self;
}

sub rank_rules {}

sub get_route {
    my ($self, $ctx) = @_;

    my @rules = $self->rules->search($ctx);

    return unless @rules;

    if (@rules > 1) {
        $self->rank_rules(\@rules);
    }

    $self->rules->set_ctx(\@rules, $ctx);

    my $rule = $rules[0];
    INFO "\e[38;5;172m" . Dumper($rule) . "\e[0m";
    $ctx->rule( $rule->name );
    $ctx->gate( $self->gates->get_gate($rule->gate) );


    my $replace;
    if ( $rule->has_replaces ) {
        if (my $r = $rule->get_replaces($ctx)) {
            if ($r->{gate}) {
                my $gate = $self->gates->get_gate($r->{gate});
                $ctx->gate($gate) if $gate;
            }

            $replace->{$_} = $r->{$_} for keys %$r;
        }
    }

    if ($rule->extra) {
        $replace->{$_} = $rule->extra->{$_} for keys %{$rule->extra};
    }

    $ctx->replace($replace) if $replace;

    1;
}


1;
