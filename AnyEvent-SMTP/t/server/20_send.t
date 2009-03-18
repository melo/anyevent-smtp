#!perl

use strict;
use warnings;
use lib './t/tlib';
use Test::More 'no_plan';
use AnyEvent::SMTP::Server;
use FakeHandle;

my $srv = AnyEvent::SMTP::Server->new;
my $sess = AnyEvent::SMTP::Server::Session->new({
  server => $srv,
  host   => '127.0.0.1',
  port   => '1212',
});

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
