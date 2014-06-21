#!/usr/bin/perl
#
#

use common::sense;


use Devel::Peek;
use POSIX;
use IO::Select;
use Term::Cap;
use Term::ANSIColor;


my $term = config_term();
print $term->Tgoto('cm', 1, 1);
print $term->Tputs('cd', 1);
print colored("Queue        Count   \n", 'green bold');
say 'v'x42 for 1..13;




sub config_term {
    my $tios = POSIX::Termios->new();
    $tios->getattr(1);
    my $term = Term::Cap->Tgetent({OSPEED => $tios->getospeed()});

    eval { $term->Trequire( qw/cm cl cd co/ ) };
    if ($@) {
        die $@;
    }

    $term;

}






