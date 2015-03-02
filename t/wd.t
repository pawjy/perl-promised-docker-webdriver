use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use Test::More;
use Test::X1;
use Promised::Docker::WebDriver;
use Web::UserAgent::Functions qw(http_get);

for my $browser (qw(chrome chromium firefox)) {
  test {
    my $c = shift;
    my $server = Promised::Docker::WebDriver->$browser;
    $server->start->then (sub {
      my $url = $server->get_url_prefix;
      return Promise->new (sub {
        my ($ok, $ng) = @_;
        http_get
            url => "$url/status",
            anyevent => 1,
            cb => sub {
              my $res = $_[1];
              test {
                ok $res->content;
              } $c;
              $ok->();
            };
      });
    })->then (sub {
      return $server->stop;
    })->then (sub {
      done $c;
      undef $c;
    });
  } n => 1, name => $browser;
}

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
