package SO::BulkGate::Constants;

use common::sense;


my %constants = (
    S_SMS_DELIVERED     =>  0,
    S_SMS_BUFFERED      =>  1,
    S_SMS_ABSENT        =>  2,
    S_SMS_PREPARING     =>  3,
    S_SMS_PROCESS       =>  4,

    S_SMS_NOT_DELIVERED => -1,
    S_SMS_EXPIRED       => -2,
    S_SMS_REJECTED      => -3,
    S_SMS_BLOCKED       => -5,
    S_SMS_NOT_SENT      => -6,

    S_APP_STATUS      => -10,
    S_ROUTE_NOT_FOUND => -10,
);


my %tags = (
    status => [ grep /^S_/, keys %constants ],
);


sub import {
    my $class = shift;

    my @methods;
    my @args = @_;
    foreach (@args) {
        if ( s/^:// ) {
            die "tag ':$_' not exists" unless $tags{$_};
            push @methods, @{$tags{$_}};
        }
        else {
            die "method '$_' not exists" unless exists $constants{$_}; 
            push @methods, $_;
        }
    }
    @methods = keys %constants unless @methods;

    my $caller = caller;
    my $symtab = \%{$caller . '::'};
    my %declared;
    
    foreach my $method ( @methods ) {
        next if $declared{$method}++;
        my $value = $constants{$method};
        Internals::SvREADONLY($value, 1);
        $symtab->{$method} = \$value;
    }

    mro::method_changed_in($caller);
}

1;
