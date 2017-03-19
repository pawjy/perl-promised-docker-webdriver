use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use Test::More;
use Test::X1;
use Promised::Flow;
use Promised::Command;

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promised::Docker::WebDriver;
    my $server = Promised::Docker::WebDriver->chrome;
    my $cv = AE::cv;
    $server->start_timeout (500);
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
      return promised_wait_until {
        return (defined $stderr and $stderr =~ /^cid=\w+$/m);
      } timeout => 500;
    });
  })->then (sub {
    $stderr =~ /^cid=(\w+)$/m;
    my $cid = $1;
    test {
      ok not `docker ps --no-trunc | grep \Q$cid\E`;
    } $c;
  })->catch (sub {
    warn $_[0];
    warn "STDERR: |$stderr|";
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
    $server->start_timeout (500);
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
      return promised_wait_until {
        return (defined $stderr and $stderr =~ /^cid=\w+$/m);
      } timeout => 500;
    });
  })->then (sub {
    $stderr =~ /^cid=(\w+)$/m;
    my $cid = $1;
    test {
      ok not `docker ps --no-trunc | grep \Q$cid\E`;
    } $c;
  })->catch (sub {
    warn $_[0];
    warn "STDERR: |$stderr|";
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
      $server->start_timeout (500);
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
      return promised_wait_until {
        return (defined $stderr and $stderr =~ /^cid=\w+$/m);
      } timeout => 500;
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
      warn "STDERR: |$stderr|";
      test { ok 0 } $c;
    })->then (sub {
      done $c;
      undef $c;
    });
  } n => 1, name => [$signal], timeout => 600;
}

run_tests;

=head1 LICENSE

Copyright 2015-2017 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
