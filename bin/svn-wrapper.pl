#!/usr/bin/perl
use strict;
use warnings;
use feature 'say';
use Carp;
use Cwd;
use Getopt::Long;

BEGIN {
    my $SVN;
    -x $_ and $SVN = $_ and last for qw!/usr/bin/svn /usr/local/bin/svn!;
    $SVN || say 'svn not found' && exit 1;
    sub exec_svn() {
        exec $SVN 'svn', @ARGV;
        Carp::croak "exec: $!";
    }
}

exec_svn unless @ARGV;


my $hooks_dir = "$ENV{HOME}/.subversion/hooks";
exec_svn unless -d $hooks_dir;

my $action = $ARGV[0];
if ($action =~ /^(?:commit|ci)$/ && -x "$hooks_dir/client-pre-commit") {
    my $argv = eval { parse_argv(@ARGV[1..@ARGV-1]) };
    exec_svn if $@;

    my @files = @{ delete $argv->{_files} };
    my @hook_args;
    if ($argv->{'config-dir'}) {
        push @hook_args, '--config-dir' => $argv->{'config-dir'};
    }
    my $st = system("$hooks_dir/client-pre-commit", @hook_args, @files);
    if ($st != 0) {
        say 'client-pre-commit return error';
        exit;
    }
}

exec_svn;

sub parse_argv {
    my @argv = @_;
    return unless @argv;
    my @opts;
    while (<DATA>) {
        s/#.*$//;
        next if /^\s*$/;
        my $opt = join '|', /(?:-+([^\s]+))+/g;
        $opt .= '=s' if /ARG/;
        push @opts, $opt;
    }
    my %flush;
    Getopt::Long::GetOptionsFromArray(\@argv, \%flush, @opts) or die 42;
    if ($flush{targets}) {
        if ( open my $fh, '<', $flush{targets} ) {
            while ($fh) {
                push @argv, $_;
            }
            close $fh;
        }
    }
    $flush{_files} = \@argv;
    return \%flush;
}



__DATA__
  -q --quiet               # print nothing, or only summary information
  -N --non-recursive       # obsolete; try --depth=files or --depth=immediates
  --depth ARG              # limit operation by depth ARG ('empty', 'files',
  --targets ARG            # pass contents of file ARG as additional args
  --no-unlock              # don't unlock the targets
  -m --message ARG         # specify log message ARG
  -F --file ARG            # read log message from file ARG
  --force-log              # force validity of log message source
  --editor-cmd ARG         # use ARG as external editor
  --encoding ARG           # treat value as being in charset encoding ARG
  --with-revprop ARG       # set revision property ARG in new revision
  --changelist --cl ARG    # operate only on members of changelist ARG
  --keep-changelists       # don't delete changelists after commit
  --username ARG           # specify a username ARG
  --password ARG           # specify a password ARG
  --no-auth-cache          # do not cache authentication tokens
  --non-interactive        # do no interactive prompting
  --trust-server-cert      # accept SSL server certificates from unknown
  --config-dir ARG         # read user configuration files from directory ARG
  --config-option ARG      # set user configuration option in the format:
