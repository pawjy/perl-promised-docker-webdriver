use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use AnyEvent;
use AnyEvent::HTTPD;
use Promise;
use Promised::Docker::WebDriver;
use Web::UserAgent::Functions qw(http_get http_post_data);
use JSON::PS;

my $server = Promised::Docker::WebDriver->chrome;
#my $server = Promised::Docker::WebDriver->firefox;

my $cv = AE::cv;

sub post ($$) {
  my ($url, $json) = @_;
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    http_post_data
        url => $url,
        content => perl2json_bytes ($json || {}),
        timeout => 100,
        anyevent => 1,
        cb => sub {
          my (undef, $res) = @_;
          if ($res->code == 200) {
            my $json = json_bytes2perl $res->content;
            if (defined $json and ref $json) {
              $ok->($json);
            } else {
              $ng->($res->code . "\n" . $res->content);
            }
          } elsif ($res->is_success) {
            $ok->({status => $res->code});
          } else {
            $ng->($res->code . "\n" . $res->content);
          }
        };
  });
} # post

sub http_server ($) {
  my $port = shift;
  my $httpd = AnyEvent::HTTPD->new (port => $port);
  $httpd->reg_cb (
    '' => sub {
      my ($httpd, $req) = @_;
      $req->respond ({content => ['text/plain', 'abc']});
    },
  );
  return $httpd;
} # http_server

my $httpd_port = Promised::Docker::WebDriver::_find_port;
my $httpd = http_server ($httpd_port);

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
  })->then (sub {
    return post ("$url/session", {
      desiredCapabilities => {
        browserName => 'firefox',
      },
    });
  })->then (sub {
    my $json = $_[0];
    my $sid = $json->{sessionId};
    my $host = $server->get_docker_host_hostname_for_container . ':' . $httpd_port;
    return post ("$url/session/$sid/url", {
      url => qq<http://$host/>,
    })->then (sub {
      return post ("$url/session/$sid/execute", {
        script => q{ return document.documentElement.textContent },
        args => [],
      });
    })->then (sub {
      my $value = $_[0]->{value};
      warn $value;
    });
  });
})->catch (sub {
  warn $_[0];
})->then (sub {
  return $server->stop;
})->then (sub {
  $httpd->stop;
  $cv->send;
});

$cv->recv;
