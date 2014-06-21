package SO::BulkGate;

use common::sense;
use Data::Dumper;


our $VERSION = 0.013;



use JSON::XS;

use AnyEvent;
use AnyEvent::HTTP;

use SO::BulkGate::Config;
use SO::BulkGate::Constants qw/:status/;
use SO::BulkGate::Ctx;
use SO::BulkGate::LogWrap;

my $R = "\e[0m";
my ($E1, $E2, $E3) = map "\e[38;5;${_}m", qw/161 33 47/;


sub now { int AE::now() };

sub MAX_SEND_TRIES() { 2 }

use Class::XSAccessor
    accessors => [ qw/
        worker
        router 
        kannel
        redis 
        dbworker 
        phoneinfo 
        ctx_cache
        back_urls
        gates
        / 
    ]
;


my $JSON = JSON::XS->new;
sub new {
    my $class = shift;
    my %args  = @_;

    bless my $self = {}, $class;

    my $conf = SO::BulkGate::Config->instance;

    $self->worker( $args{worker} );
    $self->router( $conf->router );
    $self->kannel( $conf->kannel );
    $self->gates( $conf->gates );
    $self->redis ( $args{redis} );
    $self->dbworker ( $args{dbworker} );
    $self->phoneinfo( $args{phoneinfo} ); 
    $self->ctx_cache( BulkGate::CtxCache->new( now ) );
    $self->back_urls( $conf->back_urls );


    *SO::BulkGate::Ctx::now = sub { int AE::now };

    return $self;
}


sub recv_sms {
    my ($self, $data) = (shift, shift);

    INFO "Incoming sms [$self->{worker}]: ", $data;

    $self->preprocess_sms($data);

    my $ctx = SO::BulkGate::Ctx->new($data);

    $self->route_sms($ctx);
}

sub recv_dlr {
    my ($self, $dlr) = @_;

    INFO 'reciev dlr: ', $dlr;

    $self->preprocess_dlr($dlr);

    $self->load_ctx( $dlr->{id}, 

        sub {
            my $data = shift;

            unless ($data) {
                WARN 'context not found', $dlr;
                return;
            }

            my $ctx = SO::BulkGate::Ctx->restore($data);


            my $gate = $self->router->get_gate($ctx->route); 
            my $res;
            unless ($gate) {
                ERROR 'load context: route not found', $ctx;
                $res = $self->dlr_maybe_kannel($dlr)
            }
            else {
                $res = $gate->process_dlr($dlr, $ctx);
            }


            $ctx->update($res);

            $self->process_dlr($ctx);
        }
    );
}



sub preprocess_sms {
    my ($self, $data) = (shift, shift);

    $data->{text} ||= delete $data->{txt};

    unless ( defined $data->{mccmnc} && $data->{cn} ) {
        my $info = $self->phoneinfo->get_info($data->{to});
        $data->{mccmnc} = $info->{mccmnc};
        $data->{cn}     = $info->{cn};
    }
}


sub preprocess_dlr {}


sub process_dlr {
    my ($self, $ctx) = @_;

    if ($ctx->status > S_SMS_DELIVERED) {
        INFO 'sms in process [tid ' . $ctx->tid . ']';
        return $self->stat_update($ctx);
    }
    elsif ($ctx->status < S_SMS_DELIVERED) {

        if ( $ctx->expired ) {
            $ctx->status( S_SMS_EXPIRED );
        }
        elsif ( $ctx->try + 1 > MAX_SEND_TRIES ) {
            $ctx->try( $ctx->try + 1 );
            $ctx->status(S_SMS_NOT_DELIVERED);
        }
        else {
            $ctx->new_try();
            return $self->route_sms($ctx);
        }
    }
    else {
        $ctx->status(S_SMS_DELIVERED);
    }

    $self->finish_process($ctx);
}

sub log_ctx {
    my ($self, $ctx, $pref) = @_;

    state $descr = {
        &S_SMS_DELIVERED       => 'sms delivered',
        &S_SMS_NOT_DELIVERED   => 'sms not delivered',
        &S_SMS_PROCESS         => 'sms start process',
        &S_SMS_EXPIRED         => 'sms expired',
        &S_SMS_REJECTED        => 'sms rejected',
        &S_SMS_BLOCKED         => 'sms blocked',
        &S_ROUTE_NOT_FOUND     => 'route not found',
    };
    
    my ($c, $r) = $ctx->status < 0 ? ("\e[38;5;165m", "\e[0m") : ('', ''); 

    $pref //= '';
    INFO "$c$pref" . ($descr->{$ctx->status} // 'status ' . $ctx->status), 
         $ctx, $r;
}

sub finish_process {
    my ($self, $ctx) = @_;

    $self->log_ctx($ctx, 'finish');

    $self->forward_dlr($ctx);

    $self->delete_ctx($ctx);
    $self->stat_update($ctx);
}

sub dlr_maybe_kannel {
    my $res = {};
    if ( ref $_[1] eq 'HASH' ) {
        $res = SO::BulkGate::Interface::Kannel->process_dlr($_[1]);
    }

    return $res;
}


sub log_foundroute {
    my ($self, $ctx) = (shift, shift);

    INFO "${E2}found route: gate " . $ctx->gate->name 
        . ', rule ' . $ctx->rule . ', tid [' . $ctx->tid . "]${R}";
}

sub route_sms {
    my ($self, $ctx, $cb) = @_;

    if ( $ctx->force_gate ) {
        my $gate = $self->gates->get_gate($ctx->force_gate);
        if ($gate) {
            $ctx->gate($gate);
            $ctx->try(MAX_SEND_TRIES);
        }
        else {

            ERROR 'Invalid gate name: ' . $ctx->force_gate 
                    . ' [' . $ctx->tid . ']';
            return;
        }
    }
    else {
    
        my $res = $self->router->get_route($ctx);

        unless ($res) {
            $ctx->status(S_ROUTE_NOT_FOUND);
            $self->finish_process($ctx);
            return;
        }

        $self->log_foundroute($ctx);
    }


    $self->save_ctx($ctx);

    if ($ctx->try > 1) {
        $self->stat_update($ctx);
    }
    else {
        $self->stat_add($ctx);
    }

    DEBUG 'try send: ', $ctx;

    my $request = $self->kannel->make_request($ctx);

    $self->send_http(
        $ctx,
        $request, 
        $self->kannel->on_response,
    );
} 



sub transfer_dlr {
    my ($self, $ctx) = @_;

    my $url_code = $ctx->dlr or return;

    my $tid = $ctx->tid;

    DEBUG "${E1}transfer dlr, status: $ctx->{status} [tid $tid]${R}";
  
    my $url = $self->back_urls->{$url_code};
    unless ($url) {
        ERROR "unknown forward dlr code '$url_code' [tid $tid]";
        return;
    }

    my $params = $ctx->dlr_hash;
    $url .= join '&', map {+"$_=" . url_encode($params->{$_})} keys %$params;


    $self->send_http(
        $ctx, 
        [ GET => $url ]
    );
}




sub send_http {
    my ($self, $ctx, $request, $cb) = @_;


    my ($method, $url, $headers) = @$request;
    my $tid = $ctx->tid;

    DEBUG "${E2}SEND_HTTP: $url [tid $tid]${R}";


    http_request $method, $url, @{$headers || []}, 
        sub {
            if (defined $_[0]) {
                INFO "${E3}SEND_HTTP: $_[1]->{Status} [tid $tid]${R}";
            }
            else {
                ERROR "${E1}SEND_HTTP: $_[1]->{Status} [tid $tid]${R}";
            }

            $cb->($_[0]) if $cb;
        }
    ; 
} 



sub stat_add {
    my ($self, $ctx) = (shift, shift);

    my %p = map {$_ => $ctx->{$_}} qw/id status cn partner_id from to/;
    INFO "\e[38;5;175m save: " . Dumper($ctx) . "\e[0m";
    $p{context_json} = encode_json $ctx->TO_JSON;
    $p{time}         = now();

    $self->dbworker->send_request(
      {
        params => \%p,
        type   => 'insert',
        name   => 'statistics',
        table  => 'sendsms_stat', 
      },

      { on_error => sub { ERROR "stat_add: $_[0]" } }
    );
}

sub stat_update {
    my ($self, $ctx) = (shift, shift);

    my %p = map {$_ => $ctx->$_()} qw/id try status money_spent/;
    $p{route} = $ctx->gate ? $ctx->gate->name : 'undefined';
    $p{time} = $ctx->ts;
    $p{money_spent} //= 0;
    $p{route} //= 'not found';


    $self->dbworker->send_request (
      {
        params => \%p,
        type   => 'update',
        name   => 'statistics',
        table  => 'sendsms_stat',
      }, 
      { on_error => sub { ERROR "stat_update: $_[0]" } },
    );
}



sub ctx_storage_id {
    return "ctx:$_[1]";
}


sub save_ctx {
    my ($self, $ctx, $cb) = @_;

    my $id = $ctx->id;

    INFO "\e[38;5;175m save: " . Dumper($ctx) . "\e[0m";

    $self->ctx_cache->set($ctx);

    return unless $ctx->ttl > 0;

    $self->redis->setex( 
        $self->ctx_storage_id($id), 
        $ctx->ttl,
        encode_json($ctx->TO_JSON), 
        sub {
            if ($_[1]) {
                ERROR "store context: $_[1]", $ctx->TO_JSON();
                return;
            }

            $cb->($ctx) if $cb;
        }
    );
}


sub load_ctx {
  my ($self, $id, $cb) = @_;

  my $ctx = $self->ctx_cache->get($id);

  return $cb->($ctx) if $ctx;


  $self->redis->get( 
      $self->ctx_storage_id($id), 
      sub {
          if ( $_[1] ) {
              ERROR "load_context: $_[1]";
              return;
          }

          return $cb->() unless $_[0];

          my $ctx = eval { 
              utf8::encode($_[0]);
              decode_json $_[0] 
          };

          if ($@) {
              ERROR "decode context failed: $@; $_[0]";
          }

          $cb->($ctx);
      }
  );
}


sub delete_ctx {
    my ($self, $ctx) = (shift, shift);
    
    $self->ctx_cache->del($ctx->id);

    $self->redis->del( 
        $self->ctx_storage_id($ctx->id), 
        sub {
            if ($_[1]) {
                ERROR "delete context for redis: $_[1]";
            }
        } 
    );
}



package BulkGate::CtxCache;

use common::sense;


sub new {
    my $class = shift;
    bless {_cache => {}, _current => int $_[0]}, $class;
}

sub set {
    my ($self, $ctx) = (shift, shift);


    my $ts = $ctx->ts - $ctx->ts % 600; 

    $self->{_cache}{$ts}{$ctx->id} = $ctx;

    if ($self->{_current} != $ts) {
        $self->{_current} = $ts;
        $self->{_cache} = {
            $ts - 600  => $self->{_cache}{$ts - 600},
            $ts - 1200 => $self->{_cache}{$ts - 1200},
#            $ts - 7200 => $self->{_cache}{$ts - 7200},
        };
    }
}


sub get {
    my ($self, $id) = (shift, shift);

    my $ctx;
    foreach my $ts ( sort {$b <=> $a} keys %{$self->{_cache}} ) {
        last if $ctx = $self->{_cache}{$ts}{$id};
    }
    $ctx;
}

sub del {
    my ($self, $id) = (shift, shift);

    foreach my $ts ( sort {$b <=> $a} keys %{$self->{_cache}} ) {
        last if delete $self->{_cache}{$ts}{$id};
    }
}


1;
