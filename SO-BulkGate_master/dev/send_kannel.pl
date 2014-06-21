#!/usr/bin/perl
#
#



use common::sense;
use Data::Dumper;

use Sys::Hostname;

use Encode;
use URL::Encode::XS qw/url_encode/;



use Getopt::Long;




my %KANNELS = (
    fiona => 'http://l-4.aqq.me:43038/sm',
    amy   => 'http://a.aqq.me:43038/sm',
    bulk2 => 'http://95.163.74.16:43038/sm',
);

my %DLR = (
    map { +"bulk$_" => "http://bulk-gate-$_.aqq.me:5000/dlr.cgi" } 1..3
);
    


sub def_amy_user_pass() { user => 'smu', pass => 'uM(8x8)toS' }
sub def_dlr_port() { 5555 }

my %SPEC = (
    mt_ib_uni  => {
        user   => 'mt_ib_uni',
        pass   => 'mt_ib_uni@Abjyf',
        smsc   => 'mt_ib_uni',
        kannel => 'fiona',
#        url    => ...
    },

    neoline => {
        smsc   => 'mt_kz_neoline',
        user   => 'mt_kz_neoline',
        pass   => 'mt_kz_neoline@Abjyf',
        kannel => 'bulk2',
    },

);


my ($kannel, %params, $url, $name, $prog, $help);
my ($dlr_url, $listen_dlr);

{
    local $SIG{__WARN__} = sub { die $_[0] };
    GetOptions(
        'help|h'         => \$help,
        'phone=s'        => \$params{to},
        'name|n=s'       => \$name,
        'file|f:s'       => sub {
                                require YAML::XS;
                                my $file = $_[1] ? $_[1]
                                                 : '/data/bulk_gate/gates.yml';
                                %SPEC = %{ YAML::XS::LoadFile($file) };
                                for (values %SPEC) {
                                    $_->{url}  ||= $KANNELS{fiona};
                                    $_->{smsc} ||= $_->{gate_id};
                                }
                            },
        'kannel|k=s'     => \$kannel,
        'smsc|s=s'       => \$params{smsc},
        'user|u=s'       => \$params{user},
        'pass=s'         => \$params{pass},
        'url=s'          => \$url,
        'params|p=s%{,}' => sub {
                                my (undef, $k, $v) = @_;
                                my %p = map {split /=/} map {split /,/} "$k=$v";
                                $params{$_} = $p{$_} for keys %p;
                             },
        'prog=s' => \$prog,
#        'dlr:s'  => sub { set_dlr_params($_[1]) },
    );
}

usage() && exit if $help;


die usage() unless $params{to};
$params{to} =~ s/^8/7/;

if ($name) {
    my $spec = $SPEC{$name};
    die "name '$name' not found" unless $spec;

    foreach ( grep !defined $params{$_}, qw/smsc user pass/ ) {
        $params{$_} = $spec->{$_};
    }

    unless ($url || $kannel) {
        if ($spec->{kannel}) {
            $kannel = $spec->{kannel};
        }
        elsif ($spec->{url}) {
            $url = $spec->{url};
        }
    }

#    unless ($url || ($url = $spec->{url})) {
#        $url = $KANNELS{$spec->{kannel}} or die "invalid kannel '$kannel'"
#            if !$kannel && $spec->{kannel};
#    }
}

die 'user required'  unless $params{user};


if ($kannel || !$url) {
    $kannel ||= 'fiona';
    $url    = $KANNELS{$kannel} or die "invalid kannel '$kannel'";
}

$url  = "http://$url" unless $url =~ m!^https?://!;
$url .= '?' unless $url =~ /\?/;
$url .= '&' unless $url =~ /\?$/;


$params{text} = $params{text} ? decode('utf-8', $params{text}) : 'Прювет';
$params{text} = encode('UCS-2', $params{text});
#$params{text} = encode('GSM0338', $params{text});
$params{coding} = 2;


$params{tid}  ||= '1234567890.' . rand 10_000;
$params{from} ||= 'Info';

if ($dlr_url) {
    $params{'dlr-mask'} = 0x1F;
    $params{'dlr-url'}  = "$dlr_url?status=%d&tid=$params{tid}&to=%p&"
                        . "try=1&id=$params{tid}";
}

$url .= join '&', map { +"$_=" . url_encode($params{$_}) } keys %params;
say "send url: $url \n";


if ($listen_dlr) {
#    local $SIG{CHLD} = 'IGNORE';

#    unless (my $pid = fork) {
#        die "fork: $!" unless defined $pid;
#        run_dlr_listener();
#        exit;
#    }
}


unless ($prog) {

    eval {

        require AnyEvent;
        require AnyEvent::HTTP;
    };

    if ($@) {
        warn 'Error loading AnyEvent or AnyEvent::HTTP. curl will be used';

        system {'curl'} 'curl', @ARGV, $url;
        say, exit;
    }



    my $cv = AE::cv();

    AnyEvent::HTTP::http_request( GET => $url, sub {
        my ($body, $head) = @_;

        $cv->send;

        say Dumper $body, $head;
    });

    $cv->recv;
}
else {
    system {$prog} $prog, @ARGV, $url;
    say;
}



#sub set_dlr_params {
#    my $dlr = shift;
#
#    if ($dlr) {
#        $dlr_url = $DLR{$dlr} and return 1;
#        unless ( $dlr =~ /^(?:\d+)?$/) ) {
#            $dlr_url = $dlr;
#        }
#    }
#
#
#    my ($host, $port) = split /:/, $dlr;
#    $port = $host, $host = '' if $host =~ /^\d+$/;
#    $host ||= get_host_ip();
#
#    unless ($host) {
#        warn "can't define host ip for built-in dlr serv\n";
#        return;
#    }
#
#    $port ||= def_dlr_port();
#    
#    $dlr_url    = "http://$host:$port/dlr.cgi";
#    $listen_dlr = ($host:$port);
#}
#
#



sub get_host_ip {

    my $host = Sys::Hostname::hostname();
    return unless $host;

    $host .= '.aqq.me' unless $host =~ /\./;
    my $addr = (gethostbyname($host))[4];
    return unless length $addr;
    $addr = join '.', unpack 'W*', $addr;

    return if $addr =~ /^127/;

    return $addr;
}


sub run_dlr_listener {

    exec {$^X} 'perl kannel_dlr_listener', '-MIO::Socket::INET',
               '-Mcommon::sense', '-E', 
               '';

    require IO::Socket::INET;
    my $sock = IO::Socket::INET->new(
        LocalAddr => $listen_dlr,
        Proto     => 'tcp',
    );

    
}




sub usage {
    say <<'__USE__';
perl send_kannel.pl --phone number --[name, user, pass, smsc, kannel, url]
                        --params param=value[,param=value]

    --help|h    - этот текст

    --phone     - номер телефона

    --kannel,k  - алиас URL в %KANNELS. 
    --url       - задать URL каннела явно

    --smsc|s   
    --user|u
    --pass|pw  - Параметры соединения для kannel. 
                 Если использовать вместе с параметром --name, 
                 эти ключи имеют приоритет, перегружая значения из name.
        
    --name|n   - название соединения в списке параметров соединений.
                 Соединения загружаются из файла, либо, если он не задан,
                 ищутся в %SPEC
    --file|f   - путь к файлу JSON с параметрами соединений. 
                 Если параметр используется без указания пути, 
                 по умолчанию используется /data/bulk_gate/gates.yml

    --params   - поля HTTP запроса к kannel. 

    --prog     - программа, выполняющая HTTP-запрос, если 
                 не установлен AnyEvent. 

    Пример:
        
        perl send_kannel.pl --phone 75553234242 --kannel fiona
                            --smsc mt_ib_uni --user mt_ib_uni 
                            --pass mt_ib_uni@Abjyf
                            --params text=aaa,from=VKcom 

        perl send_kannel.pl --phone 75553234242 -n mt_ib_uni
                            --p text='Привет',from=aaa,idp=4242
__USE__
}


