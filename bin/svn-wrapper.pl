#!/usr/bin/perl
use strict;
use warnings;
use Cwd;
use Getopt::Long;

BEGIN {
    my $SVN;
    -x $_ and $SVN = $_, last for qw!/usr/bin/svn /usr/local/bin/svn!;
    $SVN || print "svn not found\n" && exit 1;
    sub exec_svn() {
        exec $SVN 'svn', @ARGV;
        die "exec: $!\n";
    }
}

exec_svn unless @ARGV;

my $action = $ARGV[0];
if ($action =~ /^(?:commit|ci)$/) {
    my $argv = eval { parse_commit_argv(@ARGV[1..@ARGV-1]) };
    exec_svn if $@;

    my $hook = $argv->{'config-dir'} || "$ENV{HOME}/.subversion";
    $hook =~ s!/$!!;
    $hook .= '/hooks/client-pre-commit';
    exec_svn unless -x $hook;

    my @files = @{ delete $argv->{_files} };
    my @hook_args;
    if ($argv->{'config-dir'}) {
        push @hook_args, '--config-dir' => $argv->{'config-dir'};
    }
    my $st = system($hook, @hook_args, @files);
    if ($st != 0) {
        print "client-pre-commit return error status\n";
        exit;
    }
}

exec_svn;

sub parse_commit_argv {
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
            while (<$fh>) {
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
