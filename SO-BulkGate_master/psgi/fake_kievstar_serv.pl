#
#
#


use strict;
use warnings;
use utf8;
use 5.010;


use Data::Dumper;
use AnyEvent;
use Plack::Request;



package main;

use Data::Dumper;


run_psgi();


sub BG_PORT() { 7023 }

sub run_psgi {

    if ( !$ENV{FAKE_BULK} ) {

        require POSIX;
        require MIME::Base64;
        require AnyEvent::HTTP; 


        create_fake_bulk();

        return sub {
            my $env = shift;
            my $req = Plack::Request->new($env);

            return sub {
                my $r = shift;
                say "[fake_kievstar]\n", Dumper $req->headers;

                unless ( check_auth($req->header('Authorization'), $r) ) {
                    return;
                }

                my $answer = rand 10 > 3 ? answer_ok() : answer_not_ok();
                $r->([200, ['Content-Type' => 'text/xml'], [$answer]]);

                my $body = '';
                my $fh   = $req->body();
                while (<$fh>) {
                    $body .= $_;
                }

                say "[fake_kievstar] get message:\n$body";


                my $tw;
                $tw = AE::timer(1, 0, sub {
                    send_dlr($body);
                    undef $tw;
                });
            };
        };
    }
    else {
        FakeBulk->run_fake_bulk();
    }
}

sub check_auth {
    my ($auth, $r) = (shift, shift);
    
    my ($http_user, $http_pass) = ('test', 'test');

    if ($auth) {
        $auth =~ s/^Basic\s+//;
        $auth = MIME::Base64::decode_base64($auth);
        my ($user, $pass) = split /:/, $auth;
        return 1 if $user eq $http_user && $pass eq $http_pass;
    }

    $r->([
        401,
        [ 
            'Content-Type'     => 'text/plain',
            'WWW-Authenticate' => 'Basic realm: realm need;)'
        ],
        [ 'Unauthorized access forbidden' ]
    ]);
    return 0;
}


sub send_dlr {
    my $body = shift;
    say "[fake_kievstar] sendr dlr";
    my ($mid) = $body =~ /mid\s*=\s*"([^"]+)"/;
    
    unless ($mid) {
        say '[fake_kievstar ERROR] empty mid';
        return;
    }


    AnyEvent::HTTP::http_post('http://127.0.0.1:' . BG_PORT(), dlr_text($mid),
        'Content-Type' => 'text/xml',
        sub {
            say "[fake_kievstar] dlr answer:\n", Dumper \@_;
        }
    );
}

sub create_fake_bulk {

    if (my $bg_pid = fork()) {

        my $sw;
        $sw = AE::signal(INT => sub {
            kill TERM => $bg_pid;
            undef $sw;
            exit 0;
        });
    }
    else {
        die "fork: $!" unless defined $bg_pid;

        require Cwd;

        exec 'env', 'FAKE_BULK=1', 'twiggy', 
             '--listen', ':' . BG_PORT, Cwd::abs_path($0);

        die "exec: $!";
    }
}


sub answer_ok {
    return <<__XML__;
<?xml version="1.0" encoding="UTF-8"?>
<report>
    <status errorCode="0">Accepted</status>
</report>
__XML__
}

sub answer_not_ok {
    return <<__XML__;
<?xml version="1.0" encoding="UTF-8"?>
<report>
    <status error="SYNTAX ERROR" errorCode="42">Rejected</status>
</report>
__XML__
}

sub dlr_text {
    my $mid = shift;
    my $date = POSIX::strftime("%a, %d %b %Y %T %Z", localtime);
    return <<__XML__;
<?xml version="1.0" encoding="UTF-8"?>
<message mid="$mid" nodeId="0">
    <service>delivery-report</service>
    <status date="$date">Delivered</status>
</message>
__XML__
}


package FakeBulk;

use strict;
use warnings;
use 5.010;

use Data::Dumper;

sub run_fake_bulk {
    return unless $ENV{FAKE_BULK};

    AE::signal(TERM => sub {
        say '[fake_bulk] exit';
        exit;
    });

    say '[fake_bulk] start';
    $0 = 'twiggy fake_bulk';

    return sub {
        my $env = shift;
        my $req = Plack::Request->new($env);

        my $r    = $req->body;
        my $body = '';
        my $len  = $req->content_length;
        my ($rb, $off) = (0)x2;
        while ( defined($rb = $r->read($body, $len, $off)) ) {
            $len -= $rb;
            $off += $rb;
            last unless $len > 0;
        }

        say "[fake_bulk] delivery request:\n", Dumper($req->headers), $body;


        my ($status, $descr);
        if (defined $r) {
            $status = 200;
            $descr  = 'OK';
        }
        else {
            $status = 500;
            $descr  = 'Internal server error [my]';
        }
        return [$status, ['content-type' => 'text/plain'], [$descr]];
    };
}


__DATA__



use IO::Socket::INET;
use IO::Select;

sub run_fake_bulk {
    my $port = shift;

    say "[fake_bulk] $$ start";

    my $serv = IO::Socket::INET->new(
        Listen    => 5,
        LocalAddr => 'localhost',
        LocalPort => $port,
        Proto     => 'tcp',
        Bloking   => 0,
        ReuseAddr => 1,
    );
    my $sel = IO::Select->new($serv);

    my $exit;
    local $SIG{TERM} = sub { $exit = 1 };

    $| = 1;

    my %dlr;
    while (!$exit) {
        while (my @ready = $sel->can_read()) {
READY:
            foreach my $h (@ready) {
                if ($h == $serv) {
                    say '[fake_bulk]: incoming connection';
                    my $client = $h->accept();
                    $client->blocking(0);
                    $sel->add($client);
                    $dlr{$client} = {
                        status  => '',
                        headers => '',
                        body    => '',
                        clen    => 0,
                        len     => 0,
                    };
                }
                else {
                    my $rb;
                    my $buf;
                    my $dlr = $dlr{$h};
                    $DB::single = 1;
                    while ( $rb = sysread($h, $buf, 1024) ) {
                        $buf =~ tr/\015//d;

                        unless ($dlr->{status}) {
                            if ($buf =~ s#HTTP/1\.[01]\s+(\d{3})\s?.*\012##) {
                                $dlr->{status} = $1; 
                                next READY unless length $buf;
                            }
                            elsif ($buf =~ s/^POST[^\012]+\012//) {
                                $dlr->{status} = 200;
                                next READY unless length $buf;
                            }
                            else {
                                next READY;
                            }

                        }

                        unless ($dlr->{clen}) {
                            $buf = $dlr->{headers} . $buf;
                            if ($buf =~ s/^.*?
                                content-length:\s*(\d+).*?\012\012//xis
                            ) {
                                $dlr->{clen} = $1;
                                substr($dlr->{headers}, 
                                       length($dlr->{headers}) - $1, 
                                       $1, 
                                       ''
                                ); 
                            }
                            else {
                                $dlr->{headers} = $buf;
                                next READY;
                            }
                        }

                        if ($dlr->{clen}) {
                            $dlr->{body} .= $buf;
                            $dlr->{len} += length $buf;
                            if ($dlr->{len} == $dlr->{clen}) {
                                $rb = 0;
                                last;
                            }
                        }
                    }

                    say "[fake_bulk] dlr recieved";
                    say Dumper $dlr;

                    delete $dlr{$h};

                    unless (defined $rb) {
                        say "[fake_bulk] sysread ERROR: $!\n";
                        syswrite $h, "HTTP/1.1 500 Internal server error\r\n";
                    }
                    elsif ($rb == 0) {
                        syswrite $h, "HTTP/1.1 200 OK\r\n";
                    }
                    $sel->remove($h);
                    $h->close();
                }
            }
        }
    }

    say '[fake_bulk] shutdown...';
    foreach my $h ($sel->handles) {
        $sel->remove($h);
        if ($h == $serv) {
            $serv->shutdown();
        }
        $h->close();
    }
}

