#!perl

use strict;
use warnings;
use lib './t/tlib';
use Test::More 'no_plan';
use Test::Deep;
use AnyEvent::SMTP::Server;
use FakeHandle;

# count hooks called
my %called;

my $srv = AnyEvent::SMTP::Server->new({
  domain => 'example.com',
});
my $sess = AnyEvent::SMTP::Server::Session->new({
  server => $srv,
  host   => '127.0.0.1',
  port   => '1212',
});

# Mock the handle and restart the session read queue
my $handle = FakeHandle->new;
$sess->{handle} = $handle; # Bypass Mouse checks
$sess->is_reading(0);
$sess->_start_read;


### check line_in and parse_command chains
$srv->hook('line_in', sub {
  my ($ctl, $args) = @_;
  my ($session, $line) = @$args;
  isa_ok($session, 'AnyEvent::SMTP::Server::Session');
  
  $called{'line_in'}++;
  
  $called{'line_in_out'} = 'done';
  return $ctl->done if $line =~ m/^ignore /;

  $called{'line_in_out'} = 'declined';
  return $ctl->declined;
});

$srv->hook('parse_command', sub {
  my ($ctl, $args) = @_;
  my ($session, $line) = @$args;
  isa_ok($session, 'AnyEvent::SMTP::Server::Session');
  
  $called{'command'}++;
  
  $called{'command_out'} = 'done';
  if ($line =~ m/^my_command\s+(\w+)/) {
    $session->ok_250("OK [$1]");
    return $ctl->done;
  }

  $called{'command_out'} = 'declined';
  return $ctl->declined;
});


$handle->reset_write_buffer;
%called = ();
$handle->push_item("ignore me\r\n");
cmp_deeply(
  \%called,
  { line_in => 1, line_in_out => 'done' },
  'ignore input lines works',
);
is($handle->write_buffer, '');


$handle->reset_write_buffer;
%called = ();
$handle->push_item("kill me\r\n");
cmp_deeply(
  \%called,
  {
    line_in => 1, line_in_out => 'declined',
    command => 1, command_out => 'declined',
  },
  'parse_command with unkown command, declined ok',
);
is($handle->write_buffer, "500 Command unknown\r\n");


$handle->reset_write_buffer;
%called = ();
$handle->push_item("my_command yuppi\r\n");
cmp_deeply(
  \%called,
  {
    line_in => 1, line_in_out => 'declined',
    command => 1, command_out => 'done',
  },
  'parse_command with known command, accepted ok',
);
is($handle->write_buffer, "250 OK [yuppi]\r\n");
