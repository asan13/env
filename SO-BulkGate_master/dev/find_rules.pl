#!/usr/bin/perl
#
#

use common::sense;
use Data::Dumper;


use YAML::XS qw/LoadFile/;
use JSON::XS;
use Getopt::Long;

use SO::BulkGate::Route::RuleList;



my ($phone, %args, $all, $dir, @rule_types, $long);
GetOptions(
    'phone=s'         => \$phone,
    'mccmnc|m=s'      => \$args{mccmnc},
    'cn|country|c=s'  => \$args{cn},
    'from|f=s'        => \$args{from},
    'idp|partner|p=s' => \$args{partner},
    'to|t=s'          => \$args{to},
    'dir=s'           => \$dir,
    'rules=s'         => sub { push @rule_types, split /,/, $_[1] },
    'all|A'           => \$all,
    'long|l'          => \$long,
);
$dir ||= '/data/bulk_gate/rules';
@rule_types = qw/force allow advise deny/ unless @rule_types;

if ($phone) {
    $phone =~ s/^8/7/;

    require SO::PhoneInfo;
    my $ph = SO::PhoneInfo->new({def_codes => '/data/lib/Number/codes'});
    my $info = $ph->get_info($phone) or die 'can not define operator';
    $args{mccmnc} = $info->{mccmnc};
    $args{cn}     = $info->{cn};

    say join ', ', map "$_: $args{$_}", qw/mccmnc cn/;
}




my @rules;
foreach my $type (@rule_types) {

    foreach my $rule ( @{ LoadFile("$dir/$type.yml") || [] } ) {

        next unless $all || $rule->{enabled}; 

        $rule->{type}    = $type;
        $rule->{name}    = $rule->{rule_name};
        $rule->{gate_id} = $rule->{gate_id};

        foreach my $k ( qw/mccmnc partner_id from cn to/ ) {
            my $v = $rule->{$k} // $rule->{"-$k"};
            next unless $v;
            $rule->{$k} = {values => ref $v ? $v : {$v => 1}};
            $rule->{$k}{except} = 1 if $rule->{"-$k"};
        };

        $rule->{partner} = $rule->{partner_id} if $rule->{partner_id};
        push @rules, $rule;
    }

}

my $rlist = SO::BulkGate::Route::RuleList->new(\@rules);

my $ctx = PseudoCtx->new(%args);

my @result = $rlist->search($ctx);


my $j = JSON::XS->new()->pretty;
say 'found: ', scalar @result;
for my $rule (@result) {
    say $rule->name, " ($rule->{type})";
    say $j->encode({%$rule}) if $long;
}




package PseudoCtx;

use Class::XSAccessor
    accessors   => [ qw/partner mccmnc to from cn/ ],
    constructor => 'new',
;


1;
