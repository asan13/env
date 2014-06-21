use Plack::App::URLMap;
use SO::BulkGate::Util::BGLog;


my $map = Plack::App::URLMap->new();

$map->map('/'    => sub { BGLog::get_app('log', @_) });
$map->map('/tid' => sub { BGLog::get_app('msg', @_) });

$map->to_app();



