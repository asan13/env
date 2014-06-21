package SO::BulkGate::Daemon;

use common::sense;
use Data::Dumper;

our $VERSION = 0.0113;



use JSON::XS;
use AnyEvent;

use SO::DB::Worker::Client;
use SO::Qu::Reader;
use SO::PhoneInfo;
use SO::BulkGate::Config;
use SO::BulkGate;
use SO::BulkGate::LogWrap;

use parent 'SO::Daemon::AE';

sub _DEBUG() { 1 }
if (_DEBUG) {
    require Carp;
    $SIG{__DIE__} = sub {
        Carp::confess(@_);
    };
}

# HATE!!!
use fields qw/queue bulk/;
#

use Class::XSAccessor
    accessors => [ qw/queue bulk/ ],
;



sub worker_init {
    my $self = shift;

    $self->SUPER::worker_init;

    my $logger = $self->{sys_logger};
    SO::BulkGate::LogWrap->init(log => $logger);

    
    my $conf = SO::Config::Facility->get_config();
    SO::BulkGate::Config->init(config => $conf);


    $self->{bulk} = SO::BulkGate->new(
        worker   => $self->worker_number,
        logger   => $logger,
        redis    => SO::Redis::Facility->get_async_redis(),
        dbworker => dbworker_client(),
        phoneinfo => SO::PhoneInfo->new({def_codes => $conf->{def_codes}}),
    );


    $self->{queue} = $self->create_sms_queue();

    1;
}



sub make_sms_queue_name {
    shift if @_ > 2;

    my ($name, $num) = (shift, shift);
    unless ($name && defined $num) {
        die 'Invalid args, queue name and number required';
    }
    return join('_', $name, $num) . '_';
}



sub create_sms_queue {
    my $self = shift;

    my $conf = SO::Config::Facility->get_config();

    my $qname = $self->make_sms_queue_name(
        $conf->{bulk_gate}{sms_queue},
        $self->worker_number,
    );

    SO::Qu::Reader->new(
        queue      => $qname,
        on_dequeue => sub { 
            $self->on_dequeue(@_) 
        },
    );
}



sub dbworker_client {
    my $self = shift;

    SO::DB::Worker::Client->new(
        queue     => SO::Qu::Facility->get_async_queue( 'dbworker' ),
        table     => 'bulk_status',
        connector => 'bulk_gate',
        on_error  => sub {
            ERROR "DB::Worker enqueue failed for $_[1]->{id}: $_[0]";
        },
    );
}


sub worker_main {
    my $self = shift;

    $self->auto_finalize(1);
    $self->queue->start_read;
    $self->SUPER::worker_main;
}

sub worker_finalize {
    my $self = shift;

    $self->queue->stop_read ( sub {
        INFO 'queue reader stop';
        $self->maybe_finalize;
    }); 
}

sub maybe_finalize {
    my $self = shift;

    return if $self->queue->is_running;

    $self->SUPER::worker_finalize;
}

sub on_dequeue {
    my ($self, $msg) = (shift, shift);


    eval {

        if ($msg->{type} eq 'sms') {
            $self->bulk->recv_sms($msg);
        }
        elsif ($msg->{type} =~ 'dlr') {
            $self->bulk->recv_dlr($msg);
        }
        else {
            ERROR 'Bad message type: ', $msg;
        }
    };
    if ($@) {
        ERROR "on_dequeue $@";
    }
}


1;
