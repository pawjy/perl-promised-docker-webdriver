use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use Promise;
use Promised::Docker::WebDriver;
use Web::UserAgent::Functions qw(http_get);

my $server = Promised::Docker::WebDriver->firefox;

use AnyEvent;
my $cv = AE::cv;

$server->start->then (sub {
  my $url = $server->get_url_prefix;
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    http_get
        url => "$url/status",
        anyevent => 1,
        cb => sub {
          my $res = $_[1];
          warn $res->content;
          $ok->();
        };
  });
})->then (sub {
  return $server->stop;
})->then (sub {
  $cv->send;
});

$cv->recv;
