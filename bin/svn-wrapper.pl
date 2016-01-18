#!/usr/bin/perl
use strict;
use warnings;
use feature 'say';
use Carp;
use Cwd;

BEGIN {
    my $SVN;
    -x $_ and $SVN = $_ and last for qw!/usr/bin/svn /usr/local/bin/svn!;
    $SVN || say 'svn not found' && exit 1;
    sub exec_svn() {
        say "exec $SVN 'svn', @ARGV";
        Carp::croak "exec: $!";
    }
}

exec_svn unless @ARGV;


my $action = '';
for ( @ARGV ) {
    /^\b([a-z]+)\b$/ && ($action = $1, last);
}
exec_svn unless $action;

my $hooks_dir = "$ENV{HOME}/.subversion/hooks";
exec_svn unless -d $hooks_dir;

my $rep_dir = Cwd::abs_path -e $ARGV[-1] ? $ARGV[-1] : undef;
exec_svn unless $rep_dir;

if ($action =~ /^(?:commit|ci)$/ && -x "$hooks_dir/client-pre-commit") {
    my $st = system("$hooks_dir/client-pre-commit", $rep_dir, @ARGV);
    if ($st != 0) {
        say 'client-pre-commit return error';
        exit;
    }
}

exec_svn;

