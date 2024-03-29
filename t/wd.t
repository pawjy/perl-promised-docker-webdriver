use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use Test::More;
use Test::X1;
use JSON::PS;
use Promise;
use Promised::Flow;
use Promised::Docker::WebDriver;
use Web::UserAgent::Functions qw(http_post_data);
use AnyEvent::HTTPD;

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

{
  package test::Host;
  sub to_ascii { $_[0]->{invoked}++; '127.0.0.1' }
}

for my $browser (qw(chrome chromium firefox)) {
  test {
    my $c = shift;
    my $server = Promised::Docker::WebDriver->$browser;
    my $done = 0;
    my $failed = 0;
    $server->start_timeout (500);
    $server->start->then (sub {
      my $url = $server->get_url_prefix;
      return post ("$url/session", {
        desiredCapabilities => {
          browserName => 'firefox',
        },
      })->then (sub {
        my $json = $_[0];
        my $sid = $json->{sessionId} // $json->{value}->{sessionId};

        my $httpd_port = Promised::Docker::WebDriver::_find_port;
        my $text = 'abc'.$httpd_port.rand;
        my $httpd = AnyEvent::HTTPD->new (host => $server->get_docker_host_hostname_for_host, port => $httpd_port);
        $httpd->reg_cb ('' => sub {
          my ($httpd, $req) = @_;
          $req->respond ({content => ['text/plain', $text]});
        });

        my $host = $server->get_docker_host_hostname_for_container . ':' . $httpd_port;
        return post ("$url/session/$sid/url", {
          url => qq<http://$host/>,
        })->then (sub {
          return post ("$url/session/$sid/execute", {
            script => q{ return document.documentElement.textContent },
            args => [],
          })->catch (sub {
            return post ("$url/session/$sid/execute/sync", {
              script => q{ return document.documentElement.textContent },
              args => [],
            });
          });
        })->then (sub {
          my $value = $_[0]->{value};
          test {
            is $value, $text;
            $httpd->stop;
          } $c;
        });
      });
    })->catch (sub {
      warn $_[0];
      test { ok 0 } $c;
    })->then (sub {
      test {
        my $host = $server->get_hostname;
        #is $server->get_hostname, '127.0.0.1';
        ok $host =~ m{^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$}, $host;
        ok $server->get_port;
        is $server->get_host, $host.':' . $server->get_port;
        is $server->get_url_prefix, 'http://' . $server->get_host;
        is $server->get_rtp_port, undef;
        is $server->get_rtp_hostname, undef;
        isa_ok $server->completed, 'Promise';
        $server->completed->then (sub {
          $done++;
        }, sub {
          $failed++;
        });
        return undef;
      } $c;
    })->then (sub {
      return Promise->resolve->then (sub {
        test {
          is $done, 0;
          is $failed, 0;
        } $c;
      })->then (sub {
        return $server->stop;
      });
    })->then (sub {
      test {
        is $done, 1;
        is $failed, 0;
      } $c;
    })->then (sub {
      done $c;
      undef $c;
    });
  } n => 12, name => [$browser, 'access local server'], timeout => 600;

  test {
    my $c = shift;
    my $server = Promised::Docker::WebDriver->$browser;
    my $done = 0;
    my $failed = 0;
    my $host = bless {}, 'test::Host';
    my $port = Promised::Docker::WebDriver::_find_port;
    $server->start_timeout (500);
    $server->start (host => $host, port => $port)->then (sub {
      my $url = $server->get_url_prefix;
      return post ("$url/session", {
        desiredCapabilities => {
          browserName => 'firefox',
        },
      })->then (sub {
        my $json = $_[0];
        my $sid = $json->{sessionId} // $json->{value}->{sessionId};

        my $httpd_port = Promised::Docker::WebDriver::_find_port;
        my $text = 'abc'.$httpd_port.rand;
        my $httpd = AnyEvent::HTTPD->new (host => $server->get_docker_host_hostname_for_host, port => $httpd_port);
        $httpd->reg_cb ('' => sub {
          my ($httpd, $req) = @_;
          $req->respond ({content => ['text/plain', $text]});
        });

        my $host = $server->get_docker_host_hostname_for_container . ':' . $httpd_port;
        return post ("$url/session/$sid/url", {
          url => qq<http://$host/>,
        })->then (sub {
          return post ("$url/session/$sid/execute", {
            script => q{ return document.documentElement.textContent },
            args => [],
          })->catch (sub {
            return post ("$url/session/$sid/execute/sync", {
              script => q{ return document.documentElement.textContent },
              args => [],
            });
          });
        })->then (sub {
          my $value = $_[0]->{value};
          test {
            is $value, $text;
            $httpd->stop;
          } $c;
        });
      });
    })->catch (sub {
      warn $_[0];
      test { ok 0 } $c;
    })->then (sub {
      test {
        is $host->{invoked}, 1;
        is $server->get_hostname, $host->to_ascii;
        is $server->get_port, $port;
        is $server->get_host, $host->to_ascii . ':' . $server->get_port;
        is $server->get_url_prefix, 'http://' . $server->get_host;
        is $server->get_rtp_port, undef;
        is $server->get_rtp_hostname, undef;
        isa_ok $server->completed, 'Promise';
        $server->completed->then (sub {
          $done++;
        }, sub {
          $failed++;
        });
        return undef;
      } $c;
    })->then (sub {
      return Promise->resolve->then (sub {
        test {
          is $done, 0;
          is $failed, 0;
        } $c;
      })->then (sub {
        return $server->stop;
      });
    })->then (sub {
      test {
        is $done, 1;
        is $failed, 0;
      } $c;
    })->then (sub {
      done $c;
      undef $c;
    });
  } n => 13, name => [$browser, 'port specified'], timeout => 600;

  test {
    my $c = shift;
    my $server = Promised::Docker::WebDriver->$browser;
    $server->stop->then (sub {
      test {
        ok 1;
        done $c;
        undef $c;
      } $c;
    });
  } n => 1, name => 'stop before start', timeout => 600;
}

run_tests;

=head1 LICENSE

Copyright 2015-2019 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
