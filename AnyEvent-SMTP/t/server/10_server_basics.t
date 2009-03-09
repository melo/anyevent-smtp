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
  is(scalar(%{$srv->sessions}), 0);
  
  $srv->start;
  ok(defined($srv->server_guard));
  ok(defined($srv->current_port));
  is(scalar(%{$srv->sessions}), 0);
  
  my $cp = $srv->current_port;
  
  connect_to('127.0.0.1', $cp, sub {
    my ($fh, $host, $port) = @_;
    ok($_[0], 'Connected succesfully');
  
    my $sess = $srv->sessions;
    is(scalar(keys %$sess), 1);
    
    my ($session) = values(%$sess);
    ok($session);
    is($session->server, $srv);
    
    is($host, '127.0.0.1');
    is($port, $cp);
    
    my $handle; $handle = AnyEvent::Handle->new(
      fh => $fh,
      on_eof   => sub { undef $handle },
      on_error => sub { undef $handle },
    );
    $handle->push_read( line => sub {
      like($_[1], qr/^220 example.com ESMTP/);
      undef $handle;
    });
    $session->send(220, $srv->domain, 'ESMTP');
    
    run(sub {
      $srv->stop;
      ok(!defined($srv->server_guard));
      ok(!defined($srv->current_port));
  
      connect_to('127.0.0.1', $cp, sub {
        ok(!$_[0], 'No longer listening');
        
        run(sub {
          my $sess = $srv->sessions;
          is(scalar(keys %$sess), 0);
        
          $test_run->send;
        });
      });
    });
  });
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
  my ($host, $port, $cb) = @_;
  return tcp_connect($host, $port, $cb, sub { return 3 });
}
