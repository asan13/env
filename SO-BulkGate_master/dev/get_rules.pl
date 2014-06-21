#!/usr/bin/perl
#
#

use common::sense;

use Data::Dumper;

unless (@ARGV || -p \*STDIN || -s _) {
    die 'file not found';
}


    

my (%gates, %rules);
while (<>) {
    chomp;

    my %args; 
    @args{ qw/name enabled user pass options/ } = split /\s*\|\s*/;

    next unless $args{enabled} =~ /^(?:t|f)$/;
    

    $args{enabled}  = $args{enabled} eq 't' ? 1 : 0;
    $args{options} = { map { m!^([^=]+)=(.*)$! } split /\s+(?=[^"]+=)/ };

    my $gate = construct_gate(%args);


}


sub construct_gate {
    my %args = @_;

    my $opts = $args{options};

    my %gate = (
        enabled   => $args{enable},
        user      => $args{user},
        pass      => $args{pass},
        interface => $opts->{interface} || 'kannel',
    );

    $gate{url} = $opts->{url} if $opts->{url};

    my $name = $opts->{charge};


