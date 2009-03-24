#!perl

use strict;
use warnings;
use lib './t/tlib';
use Test::More 'no_plan';
use Test::Deep;
use AnyEvent::SMTP::Server;
use AnyEvent::SMTP::Server::Commands;
use FakeHandle;

my $srv = AnyEvent::SMTP::Server->new({
  domain => 'example.com',
});
my $sess = AnyEvent::SMTP::Server::Session->new({
  server => $srv,
  host   => '127.0.0.1',
  port   => '1212',
});
my $cmds = $srv->command_handler;

### Support for the new Async::Hooks support
isa_ok($srv->hooks, 'Async::Hooks');
can_ok($srv, qw( call hook ));

my %called;
$srv->hook('test', sub {
  my ($ctl) = @_;
  $called{server}++;
  $ctl->next;
});
$sess->hook('test', sub {
  my ($ctl) = @_;
  $called{session}++;
  $ctl->next;
});
$cmds->hook('test', sub {
  my ($ctl) = @_;
  $called{cmds}++;
  $ctl->next;
});

%called = ();
$srv->call('test');
cmp_deeply(
  \%called,
  { server => 1, session => 1, cmds => 1},
  'callig hook on server, ok',
);

%called = ();
$sess->call('test');
cmp_deeply(
  \%called,
  { server => 1, session => 1, cmds => 1},
  'callig hook on session, ok',
);

%called = ();
$cmds->call('test');
cmp_deeply(
  \%called,
  { server => 1, session => 1, cmds => 1},
  'callig hook on cmds, ok',
);


### Shortcut support
can_ok($sess, qw( server hook call has_hooks_for ));
can_ok($cmds, qw( server hook call has_hooks_for ));


### send() tests
my $handle = FakeHandle->new;
$sess->{handle} = $handle; # Bypass Mouse checks

$sess->send(500, 'abcdefg');
is($handle->write_buffer, "500 abcdefg\r\n");
$handle->reset_write_buffer;

$sess->send(500, ['abcdefg', '1234']);
is($handle->write_buffer, "500 abcdefg 1234\r\n");
$handle->reset_write_buffer;

$sess->send(500, 'dddfffggg', ['abcdefg', '1234'], 'aabbccdd');
is($handle->write_buffer, "500-dddfffggg\r\n500-abcdefg 1234\r\n500 aabbccdd\r\n");
$handle->reset_write_buffer;
