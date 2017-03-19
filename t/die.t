use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use Test::More;
use Test::X1;
use Promised::Command;

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promised::Docker::WebDriver;
    my $server = Promised::Docker::WebDriver->chrome;
    my $cv = AE::cv;
    $server->start->then (sub {
      warn "\ncid=@{[$server->{container_id}]}\n";
      exit 0;
    }, sub {
      exit 1;
    });
    $cv->recv;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return $cmd->wait->then (sub {
      my $run = $_[0];
      test {
        ok $run->exit_code;
      } $c;
      return Promise->new (sub {
        my ($ok, $ng) = @_;
        my $time = 0;
        my $timer; $timer = AE::timer 0, 0.5, sub {
          if (defined $stderr and $stderr =~ /^cid=\w+$/m) {
            $ok->();
            undef $timer;
          } else {
            $time += 0.5;
            if ($time > 30) {
              $ng->("timeout");
              undef $timer;
            }
          }
        };
      });
    });
  })->then (sub {
    $stderr =~ /^cid=(\w+)$/m;
    my $cid = $1;
    test {
      ok not `docker ps --no-trunc | grep \Q$cid\E`;
    } $c;
  })->catch (sub {
    warn $_[0];
    test { ok 0 } $c;
  })->then (sub {
    done $c;
    undef $c;
  });
} n => 2, timeout => 600;

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promised::Docker::WebDriver;
    our $server = Promised::Docker::WebDriver->chrome;
    my $cv = AE::cv;
    $server->start->then (sub {
      warn "\ncid=@{[$server->{container_id}]}\n";
      $cv->send;
    }, sub {
      exit 1;
    });
    $cv->recv;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return $cmd->wait->then (sub {
      my $run = $_[0];
      test {
        ok $run->exit_code;
      } $c;
      return Promise->new (sub {
        my ($ok, $ng) = @_;
        my $time = 0;
        my $timer; $timer = AE::timer 0, 0.5, sub {
          if (defined $stderr and $stderr =~ /^cid=\w+$/m) {
            $ok->();
            undef $timer;
          } else {
            $time += 0.5;
            if ($time > 30) {
              $ng->("timeout");
              undef $timer;
            }
          }
        };
      });
    });
  })->then (sub {
    $stderr =~ /^cid=(\w+)$/m;
    my $cid = $1;
    test {
      ok not `docker ps --no-trunc | grep \Q$cid\E`;
    } $c;
  })->catch (sub {
    warn $_[0];
    test { ok 0 } $c;
  })->then (sub {
    done $c;
    undef $c;
  });
} n => 2, timeout => 600;

for my $signal (qw(INT TERM QUIT)) {
  test {
    my $c = shift;
    my $cmd = Promised::Command->new (['perl', '-e', q{
      use AnyEvent;
      use Promised::Docker::WebDriver;
      my $server = Promised::Docker::WebDriver->chromium;
      my $cv = AE::cv;
      my $sig1 = AE::signal INT => sub { exit 1 };
      my $sig2 = AE::signal QUIT => sub { exit 1 };
      my $sig3 = AE::signal TERM => sub { exit 1 };
      $server->start->then (sub {
        print STDERR "\ncid=@{[$server->{container_id}]}\n";
      }, sub {
        warn $_[0];
        exit 1;
      });
      $cv->recv;
    }]);
    $cmd->stderr (\my $stderr);
    $cmd->run->then (sub {
      return Promise->new (sub {
        my ($ok, $ng) = @_;
        my $time = 0;
        my $timer; $timer = AE::timer 0, 0.5, sub {
          if (defined $stderr and $stderr =~ /^cid=\w+$/m) {
            $ok->();
            undef $timer;
          } else {
            $time += 0.5;
            if ($time > 10) {
              $ng->("timeout: [$stderr]");
              undef $timer;
            }
          }
        };
      });
    })->then (sub {
      return $cmd->send_signal ($signal);
    })->then (sub {
      return $cmd->wait->catch (sub { warn $_[0] });
    })->then (sub {
      $stderr =~ /^cid=(\w+)$/m;
      my $cid = $1;
      test {
        ok not `docker ps --no-trunc | grep \Q$cid\E`;
      } $c;
    })->catch (sub {
      warn $_[0];
      test { ok 0 } $c;
    })->then (sub {
      done $c;
      undef $c;
    });
  } n => 1, name => [$signal], timeout => 600;
}

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
