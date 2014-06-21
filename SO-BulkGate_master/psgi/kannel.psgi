

use common::sense;

use POSIX qw/strftime/;
use URL::Encode::XS qw/url_decode/;
use Plack::Request;
use AnyEvent;
use AnyEvent::HTTP;


my @dlr;


my $timer;
sub start_timer {
    $timer = AE::timer 1, 0.01, sub {

        while (my $url = shift @dlr) {
            logger('[send dlr]', $url);

            http_request GET => $url, sub {
                my ($body, $hdr) = (shift, shift);
                unless ($hdr->{Status} =~ /^2/) {
                    logger('[send dlr] ERROR', "$hdr->{Status} $hdr->{Reason}");
                }
            }
        }
    };
}



my $app = sub {

    start_timer();

    return sub { 
        my $req = Plack::Request->new(shift);

        logger( url_decode($req->request_uri) );


        my $dlr_url = $req->param('dlr-url'); 
        $dlr_url =~ s/%d/1/;
        push @dlr, $dlr_url;


        return [200, [], []];
    };
}->();
    

{
    open my $log, '>>', '/logs/kannel.log' or die $!;

    sub logger {
        say strftime('%H:%M:%S', localtime), ' ', join('; ', @_);
    }
}


$app;

