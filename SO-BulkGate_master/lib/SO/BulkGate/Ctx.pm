package SO::BulkGate::Ctx;

use common::sense;


use Data::UUID;


use SO::BulkGate::Constants qw/S_SMS_PROCESS S_APP_STATUS S_SMS_NOT_DELIVERED/;
use SO::BulkGate::LogWrap;


# переопределяется из SO::BulkGate
sub now { time }


sub SMS_FIELDS() {
    qw/ tid to text from partner cn mccmnc
        transit host bulk_service_id dlr 
        charset udh priority speed meta_data /
}

sub CTX_FIELDS() {
    qw/ id ts status gate expire try money_spent
        rule replace replace_names force_gate search_ctx /
}


sub TTL() { 86400 }

use Class::XSAccessor
    accessors => [
        SMS_FIELDS,
        CTX_FIELDS,
    ]
;



my $UUID_GEN = Data::UUID->new();

sub logger {
    SO::BulkGate::LogWrap->logger;
}

sub new_sms_id() {
    join '', unpack 'H*', $UUID_GEN->create();
}


sub new {
    my ($class, $args) = (shift, shift);


    my $self;

    foreach ( grep defined $args->{$_}, SMS_FIELDS ) {
        $self->{$_} = $args->{$_};
    }

    $self->{ts}     = now();
    $self->{expire} = $self->{ts} + TTL;
    $self->{try}    = 1;
    $self->{status} = S_SMS_PROCESS;
    $self->{mccmnc} = $args->{mccmnc};
    $self->{mnc}    = substr $args->{mccmnc}, 0, 3; 
    $self->{money_spent} = 0;
    foreach ( grep defined $args->{$_}, qw/force_gate/ ) { 
        $self->{$_}  = $args->{$_};
    }
    
    $self->{id} = new_sms_id;

    bless $self, $class;
}

sub restore {
    my ($class, $args) = (shift, shift);

    my $self;

    foreach ( grep defined $args->{$_}, SMS_FIELDS, CTX_FIELDS ) {
        $self->{$_} = $args->{$_};
    }

    $self->{ts} = now();

    bless $self, $class;
}



sub new_try {
    my $self = shift;

    $self->{try}++;
    $self->{failed_routes}{$self->{route}} = 1;
}

sub update {
    my ($self, $data) = (shift, shift);

    foreach ( keys %{$data || {}} ) {
        $self->{$_} = $data->{$_};
    }
}


sub expired {
    $_[0]->{expire} < $_[0]->{ts};
}

sub ttl {
    $_[0]->{expire} - $_[0]->{ts};
}



my %ctx_to_dlr = ( 
    to      => 'phone', 
    partner => 'idp' 
);

sub dlr_hash {
    my $self = shift;

    my $hash = {
        map {$_ => $self->{$_}} grep defined, 
                qw/tid idp to from status/, 
                split /,/, $self->transit || ''  
    };

    foreach ( keys %ctx_to_dlr ) {
        $hash->{$ctx_to_dlr{$_}} = delete $hash->{$_} if exists $hash->{$_};
    }

    if ($self->status <= S_APP_STATUS) {
        $hash->{status} = S_SMS_NOT_DELIVERED;
    }

    return $hash;
}

sub params {
    my ($self) = (shift);

    my $params = {
        to      => $self->to,
        from    => $self->from,
        text    => $self->text,
        ($self->udh     ? (udh      => $self->udh)     : ()),
        ($self->charset ? (charset  => $self->charset) : ()),
    };

    if ($self->replace) {
        $params->{$_} = $self->replace->{$_} for keys %{$self->replace};
    }

    $params;
}


sub TO_JSON {
   my $h = {%{$_[0]}};
   delete $h->{gate};
   $h;
}

1;

