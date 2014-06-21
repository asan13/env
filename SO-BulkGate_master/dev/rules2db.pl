#!/usr/bin/perl
#
#


use strict;
use warnings;
use 5.010;


use DBI;
use JSON::XS;
use YAML::XS;

my $dbh = DBI->connect(
    'dbi:Pg:dbname=bulk_gate',
    'bulk',
    undef,
    { RaiseError => 1 }
) or die $DBI::errstr;

die 'invalid args' if @ARGV < 2;
my ($type, $file) = @ARGV;

my $rules = YAML::XS::LoadFile($file);

my $sth = $dbh->prepare( <<__SQL__ );
    INSERT INTO rules(name, type, value) VALUES(?, ?, ?)
__SQL__

eval {
    $dbh->{AutoCommit} = 0;

    for my $rule ( @$rules ) {
        my $name = delete $rule->{rule_name};
        $rule->{weight} = delete $rule->{gate_weight} if $rule->{gate_weight};
        $rule->{gate}   = delete $rule->{gate_id}     if $rule->{gate_id};
        delete $rule->{forced};
        my $ff = delete $rule->{force_from};

        foreach my $v ( values %{$rule} ) {
            next unless ref $v eq 'HASH';
            delete $v->{none};
        }

        $sth->execute($name, $type, encode_json($rule));

        if ($ff) {
            $sth->execute( 
                $name, 'replace', 
                encode_json({
                    rule => $name, from => $ff
                })
            );
        }
    }


    $dbh->commit;
};

if ($@) {
    say "$@";
    $dbh->rollback;
}



