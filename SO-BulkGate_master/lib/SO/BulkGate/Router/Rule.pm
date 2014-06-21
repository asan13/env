
use common::sense;

package Router::Rule::Base;

use Class::XSAccessor
    accessors => [ qw/name _match/ ],
;


sub new {
    my ($class, $args, $vals) = @_;

    bless my $self = {}, $class;

    foreach my $key ( $self->RULE_FIELDS ) {
        $self->{$key} = $args->{$key} if exists $args->{$key};
    }

    if ($vals) {
        foreach my $key ( $self->RULE_VALUES ) {
            $self->{$key} = $vals->{$key} if exists $vals->{$key};
        }
    }

    $self;
}


sub match {
    $_[0]->_match->(@_);
}



sub match_field {
    my ($self, $name, $values) = @_;

    return 0 unless exists $self->{$name};

    my $match;
    foreach my $val ( ref $values ? keys %$values : $values ) {
        my $field = $self->{$name}{value};
        return if ref $val eq 'Reqexp' && ref $field eq 'Reqexp';

        if ( ref $field eq 'HASH' ) {
            $match = $field->{$val};
        }
        elsif ( ref $field eq 'Regexp' ) {
            $match = $val ~~ /\Q$field\E/;
        }
        else {
            $match = $val eq $field;
        }

        if ($match) {
            return $self->{"except_$name"} ? 0 : 1;
        }
    }
    
    return 0;
}



sub gen_match_method {
    my ($self) = (shift);


    my $code = '';
    foreach my $name ( grep defined $self->{$_}, $self->RULE_VALUES ) {

        my $val   = $self->{$name};
        my $noneg = $self->{"except_$name"} ? '' : '!';


        $code .= "
                return 0 if !\$ctx->$name || "
        ;

        if ( ref $val eq 'HASH' ) {
            $code .= " $noneg \$self->{$name}->\{\$ctx->$name};
            ";
        }
        elsif ( ref $val eq 'Regexp' ) {
            $code .= " $noneg ( \$ctx->$name =~ /$val/ );
            ";
        }
        else {
            $code .= " $noneg ( \$ctx->$name eq '$val' );
            ";
        }
    }

    my $method_name = 'match_' . $self->name;
    $method_name =~ s/[^a-zA-Z\d_]+/_/g;
    $code = "
    sub $method_name {
        my (\$self, \$ctx) = (shift, shift);

        $code

        return 1;
    }";

    $self->{_code} = $code;

    eval $code;

    unless ($@) {
       $self->_match( $self->can($method_name) );
    }
    else {
        warn "generate match method '$method_name'. code:\n$code\n$@";
    }
}



package SO::BulkGate::Router::Rule;

use parent -norequire, 'Router::Rule::Base';

sub RULE_FIELDS() { qw/name type tariff extra gate/ }
sub RULE_VALUES() { qw/mccmnc cn partner from/ }

use Data::Dumper;

use Class::XSAccessor 
    accessors => [ 
        qw/type mccmnc cn from partner gate weight tariff extra/ 
    ],

    defined_predicates => { 
        has_replaces => 'replaces' 
    },
;


sub new {
    my ($class, $args) = (shift, shift);

    bless my $self = {}, $class;

    foreach ( grep defined $args->{$_}, RULE_FIELDS ) {
        $self->{$_} = $args->{$_};
    }

    my $vals = $args->{rule};
    foreach my $field ( grep defined $vals->{$_}, RULE_VALUES ) {

        my $val = $vals->{$field}{value};
        $val = $val->[0] if ref $val && @$val <= 1;

        if ( ref $val eq 'ARRAY' ) {
            $self->{$field} = { map {$_ => 1} @$val };
        }
        else {
            $self->{$field} = $vals->{$field}{regex} ? qr/$val/ : $val;
        }
        $self->{"except_$field"} = 1 if $vals->{$field}{except};
    }


    $self->gen_match_method();

    $self->weight( scalar grep defined $self->{$_}, RULE_VALUES );

    $self;
}

sub add_replace {
    my ($self, $name, $code) = @_;

    push @{$self->{replaces} ||= []}, [$name, $code];
}

sub get_replaces {
    my ($self, $ctx) = @_;

    my ($repl, @names);
    foreach my $r ( @{$self->{replaces} || []} ) {
        if (my $r = $r->[1]->($ctx)) {
            push @names, $r->[0];
            $repl->{$_} = $r->{$_} for keys %$r;
        }
    }

    $ctx->replace_names(\@names);

    return $repl;
}




package SO::BulkGate::Router::Rule::Replace;

use parent -norequire, 'Router::Rule::Base';

use JSON::XS;

my $J;
BEGIN {
    $J = JSON::XS->new->pretty;
}

sub RULE_FIELDS() { qw/name/ } 
sub RULE_VALUES() { qw/rulename mccmnc cn partner from gate/ }

use Class::XSAccessor
    accessors => [ qw/replace rulename mccmnc cn from partner gate/ ], 
;

sub new {
    my ($class, $args) = (shift, shift);

    my $self = $class->SUPER::new($args, $args->{condition});

    $self->replace( $args->{action} ) 
        or die q[Invalid args, 'replace' required];

    $self;
}

sub MATCH_EXCLUSIVE() { 2 }
sub MATCH_NORMAL()    { 1 }
sub MATCH_NO()        { 0 }   
sub MATCH_POSIBLE()   {   }

sub match_rule {
    my ($self, $rule) = (shift, shift);

    my ($unknown, $match);
    foreach my $rkey ( grep defined $self->{$_}, RULE_VALUES ) {

        if ($self->rulename eq $rule->name) {
            return MATCH_EXCLUSIVE;
        }

        return 0 unless $rule->{$rkey};

        my $m = $rule->match_field($rkey, $self->{$rkey});

        if ($m) {
            $match = 1;
        }
        elsif ( !defined $m ) {
            $unknown = 1;
        }
        else {
            return MATCH_NO;
        }
    }

    return MATCH_NORMAL  if $match;
    return MATCH_POSIBLE if $unknown;
}



sub get_action {
    my ($self, $rule) = (shift, shift);

    my @checks;
    foreach my $key ( RULE_VALUES ) {
        next if $key eq 'rulename';

        next unless defined $rule->$key;
        next unless ref $self->$key;
        
        push @checks, $key;
    }


    my $code = '
    sub {
        my ($ctx) = (shift);
    ';

    if ( @checks ) {

        foreach my $key ( @checks ) {
            my $val = $self->{$key};
            if (ref $val eq 'Regexp') {
                $code .= "
                return unless \$ctx->{$key} ~~ /$val/;
                ";
            }
            else {
                $code .= "
                return unless \$self->\{$key}{\$ctx->{$key}};
                ";
            }
        }
    }

    my $replace = "
        {
    ";
    foreach my $key ( keys %{$self->replace} ) {
        my $val = $self->replace->{$key};

        if ($val =~ s/^&//) {
            $DB::single = 1;
        }
        else {
            $val = qq['$val'];
        }

        $replace .= "
            $key => $val,
        ";
    }
    $replace .= "
        }
    ";

    $code .= "
        return $replace;
    }";


    say "\e[38;5;157m", $rule->name. " $self->{name}\n$code\e[0m";

    my $action = eval $code;
    if ($@) {
        warn "generate replace method: $@";
        return;
    }

    return $action;
}




1;
