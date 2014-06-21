#!perl
#
#

use common::sense;

use Data::Dumper;
use JSON::XS;
use YAML::XS qw/LoadFile/; 
use DBI;



my $dbh = DBI->connect(
    'dbi:Pg:dbname=bulk_gate;host=l-3.aqq.me',
    'bulk',
    undef,
    { RaiseError => 1 }
);

my $gates = {
    map { $_->[1] => $_->[0] } @{ 
            $dbh->selectall_arrayref('SELECT id, name FROM gates') 
        }
};

my $sth = $dbh->prepare( q|
    INSERT INTO rules(name, type, enabled, gate_id, rule)
                VALUES(?, ?, ?, ?, ?)
|);


eval {
    $dbh->{AutoCommit} = 0;

    foreach my $type ( qw/allow force advise/ ) {
        foreach my $rule ( @{ LoadFile "/data/bulk_gate/rules/$type.yml" } ) {
            my $gate_id = $gates->{$rule->{gate_id}} 
                or warn "gate_id not found:\n", Dumper $rule and next;

            my $name    = $rule->{rule_name};
            my $enabled = $rule->{enabled};

            my $value = {};
            foreach my $f ( qw/mccmnc cn from partner_id/ ) {
                my $val = $rule->{$f} || $rule->{"-$f"};

                next unless $val;

                $value->{$f}{value}   = ref $val ? [ keys %$val ] : [ $val ];
                $value->{$f}{exclude} = 1 if $rule->{"-$f"};
            }

            $value = encode_json $value;


            $sth->execute($name, $type, $enabled, $gate_id, $value);
        }
    }

    $dbh->commit;
};

if ($@) {
    say "$@";
    $dbh->rollback;
}




__END__
my $sth = $dbh->prepare( q|
    INSERT INTO gates (name, enabled, "user", pass, smsc, url)
                VALUES(?, ?, ?, ?, ?, ?)
|);

my $gates = YAML::XS::LoadFile '/data/bulk_gate/gates.yml';

eval {
    $dbh->{AutoCommit} = 0;

    foreach my $name ( keys %$gates ) {
        my $gate = $gates->{$name};
        $gate->{smsc}  = delete $gate->{gate_id};
        $gate->{url} ||= 'http://l-4.aqq.me:43038/sm';
        $gate->{url} = "http://$gate->{url}" 
            unless $gate->{url} =~ m!^https?://!;

        $sth->execute( $name, @$gate{ qw/enabled user pass smsc url/ } );
    }

    $dbh->commit;
};

if ($@) {
    say "$@";
    $dbh->rollback;
}

