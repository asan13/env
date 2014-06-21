package SO::BulkGate::Config;

use common::sense;
use Data::Dumper;

use JSON::XS;
use DBIx::RetryOverDisconnects;

use SO::BulkGate::Router::Gates;
use SO::BulkGate::Router::Rules;
use SO::BulkGate::Router;
use SO::BulkGate::Interface::Kannel;

use SO::BulkGate::LogWrap;

BEGIN {
    for ( qw/ERROR WARN/ ) {
        eval "sub $_(@) { say \@_ }";
    }
}

use Class::XSAccessor 
    accessors => {
        map {$_ => $_} 

        qw/conf connect_info dbh router gates rules kannel back_urls/
    }
;

my $instance;
sub init {

    die 'Config already init' if $instance;

    bless my $self = {}, shift;
    my $args = ref $_[0] ? {%{$_[0]}} : {@_};
    $self->conf( $args->{config} ) or die 'Invalid args: config required';


    $self->gates( SO::BulkGate::Router::Gates->new() );
    $self->rules( SO::BulkGate::Router::Rules->new() );
    $self->router( SO::BulkGate::Router->new(
        gates => $self->gates,
        rules => $self->rules,
    ));

    $self->back_urls( $self->conf->{bulk_gate}{back_urls} );

    $self->setup_connect_info();
    $self->setup_kannel();
    $self->setup_data();

    $instance = $self;
}

sub instance {
    die 'Config not initialized' unless $instance;

    $instance;
}


sub reload {
}



sub setup_kannel {
    my $self = shift;

    my $conf = $self->conf->{bulk_gate};
    my $dlr_url = $conf->{dlr_url};
    $dlr_url .= '?' unless $dlr_url =~ /\?/;
    $dlr_url .= '&' unless $dlr_url =~ /(?:\?|&)\z/;

    $self->kannel(
        SO::BulkGate::Interface::Kannel->new(dlr_url => $dlr_url)
    );
}



sub setup_connect_info {
    my $self = shift;

    my $conf = $self->conf;
    my $connector = $conf->{bulk_gate}{connector} || 'bulk_gate';
    my $conninfo  = $conf->{db}{connectors}{$connector}
        or die 'connector not found';

    $conninfo->{options}{RaiseError} = 1;
    $self->connect_info([
        $conninfo->{dsn},
        $conninfo->{user},
        $conninfo->{password},
        $conninfo->{options},
    ]);

    $self->dbh(undef);
}

sub get_dbh { 
    my $self = shift;

    return $self->dbh if $self->dbh;

    $self->dbh(
        DBIx::RetryOverDisconnects->connect( @{$self->connect_info} )
    );
}




sub get_gate {
    my ($self, $name) = (shift, shift);
    
    return $self->gates->get_gate($name);
}

sub get_rule {
    my ($self, $name) = (shift, shift);

    $self->rules->get_rule($name);
}


my %tables = (
    gates    => 'SELECT id, name, smsc, a.user, pass, url FROM gates a
                 WHERE enabled IS true',
    rules    => 'SELECT a.name, a.type, b.name as gate, a.rule 
                 FROM rules a JOIN gates b ON a.gate_id = b.id
                 WHERE a.enabled IS true AND b.enabled IS true',
    replaces => 'SELECT a.name, a.rule_id, b.name AS rulename, a.condition, a.action 
                 FROM replaces a LEFT JOIN rules b ON a.rule_id = b.id
                 WHERE a.rule_id IS NULL OR b.enabled IS true',
);

sub load_data {
    my ($self, $table, $id) = @_;

    my @data;

    my $sql = $tables{$table} or die "Invalid args \$table = '$table'";
    $sql .= ' AND a.id = ?' if $id;

    eval {
        my $dbh = $self->get_dbh;
        my $sth = $dbh->prepare($sql);

        $sth->execute($id ? $id : ());

        my %row;
        $sth->bind_columns( \@row{ @{$sth->{NAME_lc}} } );

        while ( $sth->fetch ) {
            push @data, {%row};
        }
    };
    if ($@) {
        ERROR "load from '$table': $@";
        return;
    }

    return \@data;

}


sub setup_data {
    my ($self, $args) = @_;

    $args ||= {reload => 1};
    my $reload = $args->{reload};

    eval {

        if ( $reload || $args->{gate_id} ) {
            my $gates = $self->load_data('gates', $args->{gate_id})
                or die 'can nor load gates';

            $self->gates->setup($gates, 1);
        }


        my $J = JSON::XS->new;

        if ($args->{replace_id}) {
            $reload = 1;
            delete $args->{rule_id};
            delete $args->{replace_id};
        }

        if ( $reload || $args->{rule_id} ) {

            my $rules = $self->load_data('rules', $args->{rule_id})
                or die 'can nor load rules';

            foreach my $rule ( @$rules ) {
                $rule->{rule} = $J->decode($rule->{rule});
            }
            
            my $replaces;
            unless ($args->{rule_id}) {
                $replaces = $self->load_data('replaces');
                unless ($replaces) {
                    WARN 'replaces not found';
                }

                foreach my $repl ( @{$replaces || []} ) {
                    $repl->{condition} = $J->decode($repl->{condition})
                        if $repl->{condition};
                    $repl->{condition}{rulename} = $repl->{rulename}
                        if $repl->{rulename};

                    $repl->{action} = $J->decode($repl->{action})
                        if $repl->{action};
                }
            }

            $self->rules->setup($rules, $replaces, $reload);
        }
    };

    if ($@) {
        ERROR "setup data: $@";
    }
}

1;

