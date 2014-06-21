#!/usr/bin/perl

use common::sense;


use SO::Config;
use SO::Qu::Facility;


sub SMS_QUEUE() { 'bulk_gate_sms' }


use SO::BulkGate::Daemon;



my $queues = mixin_queues();

SO::BulkGate::Daemon->run (
    config => [[{
            log => {
                sys_logger => 's.bulk_gate.bulkgate',
                biz_logger => 'b.bulk_gate.bulkgate',
            },
            qu => {queues => $queues}, 
        }], 

        qw!bulk_gate/conf db!,
    ],

    facilities => {
        worker => [ qw!Qu Redis! ],
    },
);


sub mixin_queues {

    my $conf = SO::Config->load( qw!bulk_gate/conf qu! );
    my $sms_queue = $conf->{bulk_gate}{sms_queue};
    my $n_queues  = $conf->{daemon}{workers_number}; 
    my $qu_bulk   = $conf->{&SO::Qu::Facility::CONFIG_KEY}{queues}{$sms_queue};

    my $queues;
    foreach (1..$n_queues) {
        my $name = SO::BulkGate::Daemon->make_sms_queue_name($sms_queue, $_);
        $queues->{$name} = { %$qu_bulk };
    }

    return $queues;
}

