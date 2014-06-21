#!/usr/bin/perl
#
#

use common::sense;
use Data::Dumper;

use Benchmark;

use JSON::XS;

use SO::Config::Facility;
use SO::BulkGate::Config;
use SO::BulkGate::Ctx;

use Getopt::Long;

my %ctx;
GetOptions(
    'mccmnc|m=s'  => \$ctx{mccmnc},
    'cn|c=s'      => \$ctx{cn},
    'from|f=s'    => \$ctx{from},
    'partner|p=s' => sub { @ctx{ qw/partner partner_id/ } = ($_[1])x2 },
);


SO::Config::Facility->init( qw!db bulk_gate/conf! );

my $conf = SO::BulkGate::Config->init({ 
    config => SO::Config::Facility->get_config 
});


my $ctx_class = 'SO::BulkGate::Ctx';


my @ctxs = grep( $ctx{$_}, keys %ctx ) ? $ctx_class->new(%ctx) : 
    (
        $ctx_class->new( {mccmnc => '25001', cn => 'ru', partner => '771' } ),
        $ctx_class->new( {mccmnc => '25001', cn => 'ru', from    => '2325'} ),
        $ctx_class->new( {mccmnc => '25099', cn => 'ru', partner => '771' } ),
    )
;

my $J = JSON::XS->new->pretty->allow_blessed->convert_blessed;


my $router = $conf->router;
my $script = '/home/asan/SO-BulkGate_master/dev/find_rules.pl';

for my $ctx ( @ctxs ) {
    say '='x42;

    $DB::single = 1;
    while ($router->get_route($ctx)) {
        say $ctx->rule;
        say '--- 13 --->>>';
        say Dumper $ctx;
    }
    
    say '-'x42;
    system($^X, $script, cargs($ctx)); 

    say '='x42, "\n";
}

sub cargs {
    my $ctx = shift;

    map {+"--$_" => $ctx->{$_}} grep $ctx->{$_}, qw/mccmnc cn from partner/;
}


package PseudoCtx;

sub FIELDS() { qw/mccmnc cn from partner/ }
use Class::XSAccessor
    accessors   => {
        (map {$_ => $_} FIELDS, qw/search_ctx replace/),
        partner_id => 'partner',
    },

    constructor => 'new'
;

sub cargs {
    my $self = shift;

    map {+"--$_" => $self->{$_}} grep $self->{$_}, FIELDS;
}


1;

