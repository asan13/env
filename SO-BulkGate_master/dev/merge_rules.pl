#!/usr/bin/perl
#
#

use common::sense;
use Data::Dumper;

use List::MoreUtils;
use Cwd;
use YAML::XS qw/LoadFile DumpFile/;

my ($data_dir, $extra_file) = @ARGV;


unless ($data_dir && $data_dir =~ m!^/!) {
    my $sub_dir = $data_dir || 'data';
    ($data_dir = Cwd::abs_path($0)) =~ s!(?:/[^/]+){2}$!!;
    $data_dir = Cwd::abs_path("$data_dir/$sub_dir");
}

$extra_file = $extra_file ? Cwd::abs_path($extra_file) 
            : "$data_dir/extra_rules.yml"
;

-r $_ || die "path not exists or permission danied: $_\n" 
    for ($data_dir, $extra_file)
;

my $gates = LoadFile("$data_dir/gates.yml");
my $extra = LoadFile($extra_file);
$extra = {
    map {
        my $type = $_;

        sub {
            return () unless $extra->{$type};

            my $rules = {
                map {
                    my ($rule_name, $gate_id) = @$_{ qw/rule_name gate_id/ };

                    die qq['rule_name' key must exists:\n], Dumper $_ 
                        unless $rule_name;
                    die qq[Non-existent gate '$gate_id' for '$rule_name']
                        unless $gates->{$gate_id};

                    ($rule_name => $_)
                }
                @{$extra->{$type} || []}
            };

            return ($type => $rules);
        }->();


    } keys %$extra
};

warn "Nothing for adding\n" unless keys %$extra;



my $rule_dir = "$data_dir/rules";
foreach my $type ( keys %$extra ) {

    warn("no data for '$type'") && next unless keys %{$extra->{$type} || {}};

    my $new = -r "$rule_dir/$type.yml" 
                ? { 
                    map { $_->{rule_name} => $_ }
                            @{ LoadFile("$rule_dir/$type.yml") || [] } 
                  }
                : {}
    ;

    foreach ( values %{$extra->{$type}} ) {
        die qq['$_->{rule_name}' already exists] if $new->{$_->{rule_name}};
        $new->{$_->{rule_name}} = $_;
        
    }

    YAML::XS::DumpFile("$rule_dir/$type.yml", [ map $_, values %$new ]);
}



