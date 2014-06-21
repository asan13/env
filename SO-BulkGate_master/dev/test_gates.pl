#!/usr/bin/perl
#
#

use common::sense;
use Data::Dumper;

use Sys::Hostname;
use JSON::XS;
use YAML::XS qw/LoadFile/;
use URL::Encode::XS qw/url_encode/;
use AnyEvent;
use AnyEvent::HTTP;
use Getopt::Long;




my ($phone, %params, @gates, %args);
{
    $SIG{__WARN__} = sub { die "@_" };
    GetOptions(
        'bulkname|h=s'  => \$args{bulk},
        'phone|to=s'    => \$phone,
        'params|p=s'    => sub { %params = map {split /=/} split /,/, $_[1] },
        'gates|g=s@{,}' => sub { push @gates, split /,/, $_[1] },
        'no-force|n'    => \$args{no_force},

        'all-rules|a'   => \$args{all_rules},
        'dry-run|d'     => \$args{dry_run},
        'only-send|o'   => \$args{only_send},
    );
}
die 'phone number requires' unless $phone;
$phone =~ s/^8/7/;

unless ($args{only_send}) {

    my ($mccmnc, $cn) = get_mccmnc($phone);
    my $ctx = PseudoCtx->new(
        phone   => $phone,
        mccmnc  => $mccmnc,
        cn      => $cn,
        from    => $params{from},
        partner => $params{idp},
    );
    $ctx->dump;

    @gates = get_gates_from_rules($ctx) unless @gates;
    check_gates(\@gates) if @gates;
}

unless (@gates) {
    say 'gates not found';
    exit;
}
say 'gates: ', join ', ', @gates;


my $bulk = get_bulk_addr($args{bulk});

$params{to} = $phone;
$params{tid}  //= '1234567890.42.' . int time;
$params{from} //= 'Info';

my $text = delete $params{text} || 'test';
my $num  = int rand 10_000;

my @urls = map {
            my $url  = $bulk;
            $url .= join '&', map +"$_=".url_encode($params{$_}), keys %params;
            $url .= "&force_gate=$_" unless $args{no_force};
            $url .= '&' . join '&', 
                            'text=' . url_encode("$_ $num $text");

            $url;
           } @gates;


say join "\n", @urls;


exit if $args{dry_run};


my $cv = AE::cv;
foreach my $url (@urls) {

    $cv->begin;

    http_request GET => $url, sub {
        $cv->end;

        unless ( defined $_[0] ) {
            say "ERROR:\n", Dumper $_[1];
        }

    };
}
$cv->recv;



sub check_gates {
    my $gates = shift;

    my $conf = LoadFile '/data/bulk_gate/gates.yml';

    my @res;
    foreach my $name ( @$gates ) {
        my $gate = $conf->{$name};
        say "gate '$name' not found" and next unless $gate;
        say "gate '$name' disabled"  and next unless $gate->{enabled};

        push @res, $name;
    }

    @$gates = @res unless @$gates == @res;
}

sub get_mccmnc {

    my $phone = shift;

    require  SO::PhoneInfo;

    my $ph = SO::PhoneInfo->new({def_codes => '/data/lib/Number/codes'});

    my $info   = $ph->get_info($phone) or die 'can not define operator';
    my $mccmnc = $info->{mccmnc};
    my $cn     = $info->{cn};

    return $mccmnc, $cn;
}

sub get_gates_from_rules {
    my $ctx = shift;


    my @rules;
    foreach my $type ( qw/force advise allow/ ) {
        my $file = "/data/bulk_gate/rules/$type.yml";
        foreach my $rule ( @{ LoadFile($file) || [] } ) {
            next unless $rule->{enabled};

            $rule->{type} = $type;
            $rule->{name} = $rule->{rule_name};
            $rule->{gate} = $rule->{gate_id};

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

    require SO::BulkGate::Route::RuleList;
    my $rl  = SO::BulkGate::Route::RuleList->new(\@rules);
    
    my @res;
    if ($args{all_rules}) {
        push @res, $rl->search_force($ctx);
        push @res, $rl->search_advise($ctx);
        push @res, $rl->search_allow($ctx);
    }
    else {
        @res = $rl->search($ctx);
    }

    say 'Found rules: ', join "\n", 
                         map $_->name .'('.$_->type.', '.$_->gate.')', 
                         @res;

    return map $_->gate, @res;
}


sub get_bulk_addr {
    my $bulk = shift;

    if ($bulk) {
        $bulk = "bulk-gate-$bulk" if $bulk =~ /^\d$/;
    }
    else {
        $bulk = hostname;
    }

    if ($bulk =~ /^bulk/ && $bulk !~ /aqq.me$/) {
        $bulk .= '.aqq.me';
    }
    else {
        $bulk = '127.0.0.1';
    }

    return "http://$bulk:5000/mt.cgi?";
}








package PseudoCtx;

use Class::XSAccessor
    accessors   => [ qw/partner mccmnc phone from cn/ ],
    constructor => 'new',
;

sub dump {
    my $self = shift;
    say join ', ', map {+"$_: " . $self->$_} grep defined $self->$_,
            qw/phone mccmnc cn from partner/
    ;
}


1;
