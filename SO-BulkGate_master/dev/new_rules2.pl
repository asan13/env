#!/usr/bin/perl
#
#

use common::sense;
use Data::Dumper;

use JSON::XS;

use SO::Config::Facility;
use SO::BulkGate::Config;
use SO::BulkGate::Router::Rules;


SO::Config::Facility->init( qw!db bulk_gate/conf! );

my $conf = SO::BulkGate::Config->init({
    config => SO::Config::Facility->get_config,
});


$conf->setup_data();

#say Dumper $conf->rules;




__END__

use YAML::XS qw/LoadFile/;
my $rps = LoadFile '/data/bulk_gate/rules/replace.yml';

eval {
    my $dbh = $conf->get_dbh;
    $dbh->{AutoCommit} = 0;

    my $sth = $dbh->prepare('
        INSERT INTO replaces(name, rule_id, condition, action)
        VALUES (?, ?, ?, ?)
    ');

    foreach my $name ( keys %$rps ) {

        my ($cond, $act) = @{$rps->{$name}}{ qw/condition action/ };

        $cond =~ s!\\!!g;

        my $rule_id;
        if ( $cond =~ s/\$rule->\{rule_name\}\s+eq\s+(?:\^KEY|'[^']+')\n*// ) {
            $rule_id = $dbh->selectall_arrayref(
                'SELECT id FROM rules WHERE name = ?',
                undef,
                $name
            )->[0][0];

            unless ($rule_id) {
                warn "\e[38;5;161mreplace '$name': rule not exists\e[0m";
                next;
            }
        }

        my %cond;
        $cond =~ s!'!!g;
        while ( $cond =~ /\$(?:rule|req)->\{([^}]+)\}\s+[^\s]+\s+([^&|\n]+)/g ) {
            my ($k, $v) = ($1, $2);
            $v =~ s!['\\]!!g;
            $v =~ s!\s+!!g;
            if ($v =~ m!^/!) {
                $v =~ s!/!!g;
                $cond{$k}{regex} = 1;
            }
            $cond{$k}{value} = $v;
        }


        my %act;
        while ( $act =~ m!\$replace->\{([^}]+)\}\s+[^\s]+\s+([^;]+)!g ) {
            my ($k, $v) = ($1, $2);
            $v =~ s!^\s*'!!;
            $v =~ s!\s*'$!!;
            $v =~ s!\\'!'!g;
            $act{$k} = $v;
        }

        say "\n--- 13 --->>>";
        say "$name ($rule_id)\n", Dumper $cond, $act, \%cond, \%act;
        say "--- 13 ---<<<\n";

        $sth->execute($name, $rule_id, encode_json(\%cond), encode_json(\%act)); 
    }

    $dbh->commit;
};
if ($@) {
    say "$@";
    $dbh->rollback;
}
