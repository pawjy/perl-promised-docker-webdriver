package Promised::Docker::WebDriver;
use strict;
use warnings;
our $VERSION = '1.0';
use AnyEvent;
use Promise;
use Promised::Command;
use Promised::Command::Signals;

sub chrome ($) {
  ## ChromeDriver: <https://code.google.com/p/chromium/codesearch#chromium/src/chrome/test/chromedriver/server/chromedriver_server.cc&sq=package:chromium>
  return bless {
    docker_image => 'wakaba/docker-chromedriver:stable',
    driver_command => '/cd-bare',
    driver_args => ['--port=%PORT%', '--whitelisted-ips'],
    path_prefix => '',
  }, $_[0];
} # chrome

sub chromium ($) {
  return bless {
    docker_image => 'wakaba/docker-chromedriver:chromium',
    driver_command => '/cd-bare',
    driver_args => ['--port=%PORT%', '--whitelisted-ips'],
    path_prefix => '',
  }, $_[0];
} # chromium

sub firefox ($) {
  return bless {
    docker_image => 'wakaba/docker-firefoxdriver:stable',
    driver_command => '/fx-port',
    driver_args => ['%PORT%'],
    path_prefix => '/wd/hub',
  }, $_[0];
} # firefox

{
  use Socket;
  sub _can_listen ($) {
    my $port = $_[0] or return 0;
    my $proto = getprotobyname ('tcp');
    socket (my $server, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
    setsockopt ($server, SOL_SOCKET, SO_REUSEADDR, pack ("l", 1))
        or die "setsockopt: $!";
    bind ($server, sockaddr_in($port, INADDR_ANY)) or return 0;
    listen ($server, SOMAXCONN) or return 0;
    close ($server);
    return 1;
  } # _can_listen

  sub _find_port () {
    my $used = {};
    for (1..10000) {
      my $port = int rand (5000 - 1024); # ephemeral ports
      next if $used->{$port};
      return $port if _can_listen $port;
      $used->{$port}++;
    }
    die "Listenable port not found";
  } # _find_port
}

{
  use AnyEvent::Socket;
  use AnyEvent::Handle;
  my $Interval = 0.5;
  sub _wait_server ($$$) {
    my ($hostname, $port, $timeout) = @_;

    my $connect = sub {
      return Promise->new (sub {
        my ($ok, $ng) = @_;
        tcp_connect $hostname, $port, sub {
          return $ng->($!) unless @_;
          my $hdl; $hdl = AnyEvent::Handle->new (
            fh => $_[0],
            on_error => sub { $ng->($_[2]); undef $hdl; },
            on_eof => sub { $ng->(); undef $hdl; },
          );
          $hdl->push_read (chunk => 4, sub { $ok->(); $_[0]->destroy; });
          $hdl->push_write ("HEAD / HTTP/1.0\x0D\x0A\x0D\x0A");
        };
      });
    };

    my ($ok, $ng);
    my $p = Promise->new (sub { ($ok, $ng) = @_ });
    my $try_count = 1;
    my $try; $try = sub {
      $connect->()->then (sub {
        $ok->();
        undef $try;
      }, sub {
        if ($try_count++ > $timeout / $Interval) {
          $ng->("Server does not start in $timeout s");
          undef $try;
        } else {
          my $timer; $timer = AE::timer $Interval, 0, sub {
            $try->();
            undef $timer;
          };
        }
      });
    }; # $try
    $try->();
    return $p;
  } # _wait_server
}

sub start_timeout ($;$) {
  if (@_ > 1) {
    $_[0]->{start_timeout} = $_[1];
  }
  return $_[0]->{start_timeout} || 10;
} # start_timeout

sub start ($) {
  my $self = $_[0];

  $self->{start_pid} = $$;
  $self->{port} = _find_port;

  my @args = @{$self->{driver_args}};
  for (@args) {
    s/%PORT%/$self->{port}/g;
  }

  my $ip_cmd = Promised::Command->new (['sh', '-c', q{ip route | awk '/docker0/ { print $NF }'}]);
  $ip_cmd->stdout (\my $ip);
  return $ip_cmd->run->then (sub { return $ip_cmd->wait })->then (sub {
    die $_[0] unless $_[0]->exit_code == 0;
    chomp $ip if defined $ip;
    die "Can't get docker0's IP address" unless defined $ip and $ip =~ /\A[0-9.]+\z/;
    $self->{docker_host_ipaddr} = $ip;
  })->then (sub {
    my $cmd = Promised::Command->new ([
      'docker', 'run', '-t', '-d',
      '--add-host=dockerhost:' . $self->{docker_host_ipaddr},
      '-p', '127.0.0.1:'.$self->{port}.':'.$self->{port},
      $self->{docker_image},
      $self->{driver_command}, @args,
    ]);
    $cmd->stdout (\($self->{container_id} = ''));

    $self->{running} = 1;
    my $stop_code = sub { return $self->stop };
    $self->{signal_handlers}->{$_} = Promised::Command::Signals->add_handler
        ($_ => $stop_code) for qw(INT TERM QUIT);
    return $cmd->run->then (sub {
      return $cmd->wait;
    })->then (sub {
      die $_[0] unless $_[0]->exit_code == 0;
      chomp $self->{container_id};
      return _wait_server $self->get_hostname, $self->get_port, $self->start_timeout;
    });
  });
} # start

sub stop ($) {
  my $self = $_[0];
  return Promise->resolve unless defined $self->{container_id};

  my $cmd = Promised::Command->new (['docker', 'kill', $self->{container_id}]);
  $cmd->stdout (\my $stdout);
  return $cmd->run->then (sub {
    return $cmd->wait;
  })->then (sub {
    die $_[0] unless $_[0]->exit_code == 0;
    delete $self->{signal_handlers};
    delete $self->{running};
  });
} # stop

sub get_port ($) {
  return $_[0]->{port} // die "|run| not yet invoked";
} # get_port

sub get_hostname ($) {
  die "|run| not yet invoked" unless defined $_[0]->{port};
  return '127.0.0.1';
} # get_hostname

sub get_host ($) {
  return $_[0]->get_hostname . ':' . $_[0]->get_port;
} # get_host

sub get_url_prefix ($) {
  return 'http://' . $_[0]->get_host . $_[0]->{path_prefix};
} # get_url_prefix

sub get_docker_host_hostname_for_container ($) {
  die "|run| not yet invoked" unless defined $_[0]->{port};
  return 'dockerhost';
} # get_docker_host_hostname_for_container

sub get_docker_host_hostname_for_host ($) {
  return $_[0]->{docker_host_ipaddr} // die "|run| not yet invoked";
} # get_docker_host_hostname_for_host

sub DESTROY ($) {
  my $self = $_[0];
  if ($self->{running} and
      defined $self->{start_pid} and $self->{start_pid} == $$) {
    $self->stop;
  }
} # DESTROY

1;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
