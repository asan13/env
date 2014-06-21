#!/usr/bin/perl
#
#


use common::sense;

use Data::Dumper;
use JSON::XS;
use Term::ReadKey;
use Redis;
use Text::ASCIITable;
use AnyEvent;
use Getopt::Long;

my $CONF = {
    processes => {
        bulk_gate => 'box.+?bulkgate',
        dbworker  => 'box.+?dbworker',
        frontend  => 'twiggy.+?bulk-front',
        redis     => 'redis-server',
    },

    'PS'  => 'ps ax -o user,pid,vsz,rss,%mem,%cpu,etime,args',

    redis => {
        auth => 'Geiyae7R%ibo8ai1E',

        queues => [ qw/qu_bulk_gate_sms* qu_dbworker*/ ],

        info => [ qw/
            used_memory_human 
            used_memory_peak_human 
            used_cpu_sys
            used_cpu_user
            connected_clients/
        ],
    },
    delay => 5,
}; 

read_config();

my $REDIS = connect_redis();

my $PS = q/ps ax -o user,pid,vsz,rss,%mem,%cpu,etime,args/;


main();

sub END {
    ReadMode 0;
}


sub main {
    STDOUT->autoflush(1);


    my $cv = AE::cv;
    my ($timer, $stdin);

    $stdin = AE::io \*STDIN, 0, sub {
        my $char = ReadKey -1;
        if ($char eq 'q') {
            undef $timer;
            undef $stdin;
            $cv->send();
        }
    };

    $timer = AE::timer 0, $CONF->{delay}, sub {
        my $info = get_info();
        print_info($info);
    };

    ReadMode 'cbreak';
    clear();

    $cv->recv();

    ReadMode 0;
}

sub get_info {
    return {
        processes => [ get_processes_info() ],
        redis     => get_redis_info(),
    }
}


sub print_info {
    my $info = shift;
    
    my $tp = Text::ASCIITable->new({headingText => 'Processes'});
    $tp->setCols('Name', 'pid', 'vsz', 'rss', 'memory', 'cpu', 'etime');
    foreach my $proc ( @{$info->{processes}} ) {
        for (@$proc[3,4]) {
            $_ = sprintf('%.2f%s',  
                            $_ >= 1024**3 ? ($_ / 1024**3, 'T')
                          : $_ >= 1024**2 ? ($_ / 1024**2, 'G')
                          : $_ >= 1024    ? ($_ / 1024,    'M') 
                          : ($_, '')
                        
            );
        }
        $tp->addRow($proc->[0], @$proc[2..7]);
    }

    my $rt = Text::ASCIITable->new({headingText => 'Redis info'});
    $rt->setCols('Parameter', 'Value');
    $rt->addRow ($_, $info->{redis}{info}{$_}) for @{$CONF->{redis}{info}}; 

    my $rq = Text::ASCIITable->new({headingText => 'Redis queues'});
    $rq->setCols('Name', 'length');
    $rq->addRow($_->[0], $_->[1]) for @{$info->{redis}{queues}};

    clear();
    say $tp;
    say $rt;
    say $rq;

}

sub clear {
    print "\33[H\33[J";
}


sub read_config {
    my ($delay, $conf_file);

    GetOptions(
        'conf=s'  => \$conf_file,
        'delay=i' => \$delay,
    );


    return unless $conf_file;

    require YAML::XS;
    $CONF = YAML::XS::LoadFile($conf_file);    
    $CONF->{delay} ||= 5;
}


sub get_processes_info {

    my @ps = `$PS`;

    my @procs;
    foreach my $proc (@ps) {
        my @proc = get_proc($proc);
        push @procs, \@proc if @proc;
    }

    return sort {$a->[0] cmp $b->[0]} @procs;

}


sub get_redis_info {

    my $info = $REDIS->info();

    my @names;
    foreach my $name ( @{$CONF->{redis}{queues}} ) {
        push @names, $name =~ /\*/ ? $REDIS->keys($name) : $name;
    }
    
    my @queues;
    foreach my $name (@names) {
        push @queues, [$name, $REDIS->llen($name)];   
    }

    push @queues, [ 'all keys' => $REDIS->dbsize() ];

    return {info => $info, queues => \@queues};
}

sub get_proc {
    my $get_proc = '';
    my $procs = $CONF->{processes};
    foreach my $proc ( keys %$procs ) {
        my $re = qr/$procs->{$proc}/;
        $get_proc .= qq[
            if (\$_[0] =~ /$re/) {
                return '$proc', split ' ', \$_[0], 8;
            }
        ];
    }

    no warnings 'redefine';
    eval qq[
        sub get_proc {
            $get_proc

            return;
        }
    ];
    die $@ if $@;

    &get_proc;
}


sub connect_redis {
    my $redis = Redis->new( %{$CONF->{redis}->{connect_info} || {}} );
    $redis->auth($CONF->{redis}->{auth}) if $CONF->{redis}->{auth};
    return $redis;
}


