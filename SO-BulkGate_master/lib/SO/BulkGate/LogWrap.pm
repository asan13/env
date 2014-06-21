package SO::BulkGate::LogWrap;

use common::sense;

use Data::Dumper;
use Scalar::Util qw/blessed set_prototype reftype/;
use Sub::Name;
use Data::Alias;
use JSON::XS;


my ($JSON, $LOG);
my (%LEVELS, $LEVEL);
@LEVELS{ qw/TRACE DEBUG INFO WARN ERROR FATAL/ } = (1..6);


sub logger() { $LOG };

my @deffered;

sub init {
    my $class = shift;

    if ($LOG) {
        $LOG->warn(__PACKAGE__ . ' already initialize');
        return;
    }

    my $args = ref $_[0] ? $_[0] : {@_};
    die 'logger object required' unless blessed $args->{log};

    $LOG  = $args->{log};
    $JSON = JSON::XS->new()->allow_blessed
                           ->convert_blessed;

    my $max_level = $LEVELS{ $args->{max_level} || 'TRACE' };
    unless ($max_level) {
        $LOG->error("incorect 'max_level': '$args->{max_level}'");
        $max_level = $LEVELS{TRACE};
    }
    $LEVEL = $max_level;

    no warnings 'redefine';
    while (my $def_imp = shift @deffered) {
        $def_imp->();
    }
}

sub import {
    my $class  = shift;
    my $caller = caller;

    my @args = @_;
    my $import = sub {
        my ($level, $colorize);
        while (@args) {
            my $arg = shift @args;
            if ($arg eq 'colorize') {
                $colorize = 1;
            }
            elsif ($arg eq 'level') {
                my $lval = uc shift @args or die 'level value required';
                unless ( $level = $LEVELS{$lval} ) {
                    $LOG->error("invalid level '$lval'");
                    $level = $LEVEL;
                }
            }
        }
        $level = $LEVEL unless $level && $level >= $LEVEL;


        foreach ( keys %LEVELS ) {
            my $sub;
            if ( $LEVELS{$_} < $level ) {
                $sub = sub {42};
            }
            else {
                my $method = lc $_;
                $sub = sub {
                    my $msg = _encode_msg(\@_);
                    $LOG->$method(@$msg);
                };
            }

            set_prototype(\&$sub, '@');

            my $caller_method = "$caller\::$_";
            *{$caller_method} = subname $caller_method => $sub;
        }
    };

    unless ($LOG) {
        for (keys %LEVELS) {
            *{"$caller\::$_"} = set_prototype(sub {42}, '@');
        }
        push @deffered, $import;
    }
    else {
        $import->();
    }
}

sub _encode_msg {
    my $msgs = shift;

    my @msgs;
    while ( my $msg = splice @$msgs, 0, 1 ) { 
        unless (ref $msg) {
            alias push @msgs, $msg;
            next;
        }

        push @msgs, $JSON->encode( _convert_if_blessed($msg) );
    }

    return \@msgs;
}

sub _convert_if_blessed {

    my $msg = $_[0];
    if (blessed $msg && $msg->can('TO_JSON')) {
        return $msg->TO_JSON;
    }

    my $ref_t = reftype $msg;
    my $msg_x = {};
    if ($ref_t eq 'HASH') {
        for my $k ( keys %$msg ) {
            $msg_x->{$k} = ref $msg->{$k} ? _convert_if_blessed($msg->{$k}) 
                                         : $msg->{$k};
        }
    }

    return $msg_x;
}


1;
