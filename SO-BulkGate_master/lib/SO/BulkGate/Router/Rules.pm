use common::sense;

package SO::BulkGate::Router::Rules;


use Class::XSAccessor 
    accessors => [ qw/load_ts rules allow advise force deny replaces/ ]
;

use SO::BulkGate::Router::Rule;
use SO::BulkGate::Router::Replace;

sub new {

    bless my $self = {}, shift;

    $self->{replaces} = SO::BulkGate::Router::Replace->new();    

    $self;
}



sub setup {
    my ($self, $rules, $replaces, $reload) = @_;


    unless ($reload) {
        foreach my $args ( @$rules ) {
            $self->set_rule($args);
        }

        $self->load_ts(time);

        return;
    }


    my (%rules, @rules);
    foreach my $args ( @$rules ) {
        my $rule = SO::BulkGate::Router::Rule->new($args);
        push @rules, $rule;
        push @{$rules{$rule->type} ||=[]}, $rule; 
    }

    if ($replaces) {
        $self->replaces->apply( \@rules, $replaces );
    }

    foreach my $type ( keys %rules ) {
        $self->$type( Router::Rules::List->new($rules{$type}) );
    }

    $self->rules( { map {$_->name => $_} @rules } );

    $self->load_ts(time);
}


sub set_rule {
    my ($self, $args) = (shift, shift);

    my $rule = SO::BulkGate::Router::Rule->new($args);

    if (my $old = $self->rules->{$rule->name}) {
        my $old_type = $old->type;
        $self->$old_type->delete_rule($old);
        delete $self->rules->{$old->name};
    }

    my $type = $rule->type;
    $self->$type->add_rule($rule);
}

sub get_rule {
    $_[0]->rules->{$_[1]};
}

sub search {
    my ($self, $ctx) = (shift, shift);

    my $sctx;
    my ($type, $weight);
    while ($sctx = $ctx->search_ctx) {
        if ($sctx->{ts} < $self->load_ts) {
            undef $sctx;
            last;
        }

        ($type, $weight) = @$sctx{ qw/type weight/ };

        shift @{$sctx->{rules}};
        my $rulename = $sctx->{rules}[0];

        unless ($rulename) {
            if ( $sctx->{type} eq 'force' ) {
                $ctx->search_ctx(undef);
                return;
            }

            $type   = $sctx->{type};
            $weight = $sctx->{weight};
            last;
        }

        my $rule = $self->get_rule($rulename);

        unless ($rule) {
        }

        $sctx->{ts} = $ctx->ts;
        return $rule;
    }

    my $rules;
    unless ($type) {
        $rules = $self->force->search($ctx);
    }

    unless ($rules) {
        for my $type ( $type && $type eq 'allow' ? 'allow' : qw/advise allow/ ) {
            $rules = $self->$type->search($ctx, $weight);
            last if $rules;
            undef $weight;
        }
    }


    return @{$rules || []};
}



sub set_ctx {
    my ($self, $rules, $ctx) = @_;

    if ( @{$rules || []} ) {
        $ctx->search_ctx({
            ts     => $ctx->ts,
            rules  => [ map $_->name, @$rules ],
            type   => $rules->[0]->type,
            weight => $rules->[0]->weight,
        });
    }
};




package Router::Rules::List;

use Class::XSAccessor 
    accessors => [ qw/weights/ ]
;

sub new {
    my ($class, $rules) = (shift, shift);


    bless my $self = {}, $class;

    foreach my $rule ( @$rules ) {
       $self->{r}{$rule->weight}{$rule->name} = $rule;
    }

    $self->set_weights( ); 

    $self;
}

sub set_weights {
    my $self = shift;

    $self->weights([ 
        sort {$b <=> $a} keys %{$self->{r}} 
    ]);

}


sub search {
    my ($self, $ctx, $weight) = @_;

    my @rules;
    
    foreach ( 
        $weight ? grep $_ < $weight, @{$self->weights} 
                : @{$self->weights} 
    ) {

        foreach my $rule ( values %{$self->{r}{$_}} ) {
            push @rules, $rule if $rule->match($ctx);
        }

        last if @rules;
    }

    return @rules ? \@rules : ();
}


sub add_rule {
    my ($self, $rule) = (shift, shift);
    
    $self->{$rule->weight}{$rule->name} = $rule;
    $self->set_weights();
}

sub delete_rule {
    my ($self, $rule) = (shift, shift);

    delete $self->{r}{$rule->weigth}{$rule->name};
    unless ( @{$self->{r}{$rule->weight}} ) {
        delete $self->{r}{$rule->wieght};
        $self->set_weights();
    }
}


1;
