#!perl

use strict;
use warnings;
use Test::More 'no_plan';

use AnyEvent;
use AnyEvent::SMTP::Server;
use AnyEvent::Socket;

my $test_run = AnyEvent->condvar;

# Test for proper start/stop listening socket
my $srv = AnyEvent::SMTP::Server->new({
  domain => 'example.com',
});

run(sub {
  ok($srv);
  ok(!defined($srv->server_guard));
  ok(!defined($srv->current_port));
  
  $srv->start;
  ok(defined($srv->server_guard));
  ok(defined($srv->current_port));
  
  my $cp = $srv->current_port;
  
  connect_to('127.0.0.1', $cp,
    sub {
      ok($_[0], 'Connected succesfully');
    },
    sub {
      $srv->stop;
      ok(!defined($srv->server_guard));
      ok(!defined($srv->current_port));

      connect_to('127.0.0.1', $cp,
        sub {
          ok(!$_[0], 'No longer listening');
          $test_run->send;
        },
      );
    },
  );
});


$test_run->recv;


#######
# Utils

sub run {
  my ($delay, $cb) = @_;
  
  if (ref($delay) eq 'CODE') {
    $cb = $delay;
    $delay = 0.5;
  }
  
  my $t; $t = AnyEvent->timer( after => $delay, cb => sub {
    $cb->();
    undef $t;
  });
  
  return;
}

sub connect_to {
  my ($host, $port, $test, $next) = @_;
  
  tcp_connect(
    $host, $port,
    sub {
      $test->(@_);
      $next->() if $next;
    },
    sub { return 3 },
  );
  
  return;
}
