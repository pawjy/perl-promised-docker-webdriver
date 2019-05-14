package Promised::Docker::WebDriver;
use strict;
use warnings;
our $VERSION = '3.0';
use AnyEvent;
use Promise;
use Promised::Flow;
use Promised::Command::Docker;

sub chrome ($) {
  ## ChromeDriver: <https://code.google.com/p/chromium/codesearch#chromium/src/chrome/test/chromedriver/server/chromedriver_server.cc&sq=package:chromium>
  return bless {
    docker_image => 'quay.io/wakaba/chromedriver:stable',
    driver_command => '/cd-bare',
    driver_args => ['--port=%PORT%', '--whitelisted-ips'],
    path_prefix => '',
  }, $_[0];
} # chrome

sub chromium ($) {
  return bless {
    docker_image => 'quay.io/wakaba/chromedriver:chromium',
    driver_command => '/cd-bare',
    driver_args => ['--port=%PORT%', '--whitelisted-ips'],
    path_prefix => '',
  }, $_[0];
} # chromium

sub firefox ($) {
  return bless {
    docker_image => 'quay.io/wakaba/firefoxdriver:stable',
    driver_command => '/fx-port',
    driver_args => ['%PORT%'],
    path_prefix => '',
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
  sub _wait_server ($$$) {
    my ($hostname, $port, $timeout) = @_;
    return promised_wait_until {
      return Promise->new (sub {
        my ($ok, $ng) = @_;
        tcp_connect $hostname, $port, sub {
          return $ok->(0) unless @_;
          my $hdl; $hdl = AnyEvent::Handle->new (
            fh => $_[0],
            on_error => sub { $ok->(0); undef $hdl; },
            on_eof => sub { $ok->(0); undef $hdl; },
          );
          $hdl->push_read (chunk => 4, sub { $ok->(1); $_[0]->destroy; });
          $hdl->push_write ("HEAD / HTTP/1.1\x0D\x0AHost: $hostname:$port\x0D\x0A\x0D\x0A");
        };
      });
    } timeout => $timeout, interval => 0.5;
  } # _wait_server
}

sub start_timeout ($;$) {
  if (@_ > 1) {
    $_[0]->{start_timeout} = $_[1];
  }
  return $_[0]->{start_timeout} || 10;
} # start_timeout

sub use_rtp ($;$) {
  if (@_ > 1) {
    $_[0]->{use_rtp} = $_[1];
  }
  return $_[0]->{use_rtp};
} # use_rtp

sub start ($;%) {
  my ($self, %args) = @_;

  $self->{hostname} = defined $args{host} ? $args{host}->to_ascii : '127.0.0.1';
  $self->{port} = defined $args{port} ? 0+$args{port} : _find_port;

  ($self->{completed}, $self->{send_completed}) = promised_cv;

  my @opt;
  if ($self->{use_rtp}) {
    $self->{rtp_host} = '224.0.0.56';
    $self->{rtp_port} = _find_port; # In fact this is wrong.
    push @opt, '-e', 'WD_RTP_DEST=' . $self->{rtp_host};
    push @opt, '-e', 'WD_RTP_PORT=' . $self->{rtp_port};
  }

  my @args = @{$self->{driver_args}};
  for (@args) {
    s/%PORT%/$self->{port}/g;
  }

  $self->{command} = Promised::Command::Docker->new (
    docker_run_options => [
      '-p', $self->{hostname}.':'.$self->{port}.':'.$self->{port},
      @opt,
    ],
    image => $self->{docker_image},
    command => [$self->{driver_command}, @args],
    propagate_signal => 1,
    signal_before_destruction => 1,
  );
  return $self->{command}->start->then (sub {
    die $_[0] unless $_[0]->exit_code == 0;
    return _wait_server $self->get_hostname, $self->get_port, $self->start_timeout;
  });
} # start

sub stop ($) {
  my $self = $_[0];
  return Promise->resolve unless defined $self->{command};

  my $s = delete $self->{send_completed} || sub { };
  return $self->{command}->stop (signal => 'KILL')->then (sub {
    die $_[0] unless $_[0]->exit_code == 0;
  })->finally ($s);
} # stop

sub completed ($) {
  return $_[0]->{completed} // die "|run| not yet invoked";
} # completed

sub get_port ($) {
  return $_[0]->{port} // die "|run| not yet invoked";
} # get_port

sub get_hostname ($) {
  die "|run| not yet invoked" unless defined $_[0]->{port};
  return $_[0]->{hostname};
} # get_hostname

sub get_host ($) {
  return $_[0]->get_hostname . ':' . $_[0]->get_port;
} # get_host

sub get_url_prefix ($) {
  return 'http://' . $_[0]->get_host . $_[0]->{path_prefix};
} # get_url_prefix

sub get_rtp_hostname ($) {
  return $_[0]->{rtp_host}; # or undef
} # get_rtp_hostname

sub get_rtp_port ($) {
  return $_[0]->{rtp_port}; # or undef
} # get_rtp_port

sub get_docker_host_hostname_for_container ($) {
  die "|run| not yet invoked" unless defined $_[0]->{command};
  return $_[0]->{command}->dockerhost_host_for_container;
} # get_docker_host_hostname_for_container

# OBSOLETE
sub get_docker_host_hostname_for_host ($) {
  return '0.0.0.0';
}

sub DESTROY ($) {
  $_[0]->stop;
} # DESTROY

1;

=head1 LICENSE

Copyright 2015-2019 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
