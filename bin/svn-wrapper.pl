#!/usr/bin/perl
use common::sense;
use Carp;
use Cwd;

my $SVN;
BEGIN {
    -x $_ and $SVN = $_ and last for qw!/usr/bin/svn /usr/local/bin/svn!;
    $SVN || say 'svn not found' && exit 1;
    sub exec_svn() {
        exec $SVN 'svn', @ARGV;
        Carp::croak "exec: $!";
    }
}

exec_svn unless @ARGV;


my $action = '';
for ( @ARGV ) {
    /^\b([a-z]+)\b$/ && ($action = $1 and last);
}
exec_svn unless $action;

my $repdir = repdir( -e $ARGV[-1] ? $ARGV[-1] : undef );
exec_svn unless $repdir;

my $svn_dir = "$ENV{HOME}/.subversion/hooks";
exec_svn unless -d $svn_dir;

if ($action =~ /^(?:commit|ci)$/ && -x "$svn_dir/client-pre-commit") {
    my $st = system("$svn_dir/client-pre-commit", $repdir, @ARGV);
    if ($st != 0) {
        say 'client-pre-commit return error';
        exit;
    }
}

exec_svn;


sub repdir {
    my $dir = Cwd::abs_path shift or return;
    if ( -f $dir ) {
        $dir =~ s![^/]+$!!;
        $dir =~ s!/$!!;
        $dir = '.' unless $dir;
    }

    my $exists_svn;
    while ($dir) {
        $exists_svn = 1 and last if -d "$dir/.svn";
        $dir =~ s!/?[^/]*$!!;
    }
    return '' unless $exists_svn;
    $dir = '.' unless $dir;
    return $dir;
}





