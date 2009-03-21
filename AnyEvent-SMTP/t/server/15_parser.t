#!perl

use strict;
use warnings;
use lib './t/tlib';
use Test::More 'no_plan';
use Test::Deep;
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

### Test MAIL FROM parser

my @mail_from_test_cases = (
  {
    in       => 'from:<>',
    rev_path => '',
    buffer   => "250 ok\r\n",
    ext      => {},
  },
  {
    in => 'from:<x@y>',
    rev_path => 'x@y',
    buffer => "250 ok\r\n",
    ext => {},
  },
  {
    in => 'from:x@y',
    rev_path => 'x@y',
    buffer => "250 ok\r\n",
    ext => {},
  },
  {
    in => 'from: <x@y>',
    rev_path => 'x@y',
    buffer => "250 ok\r\n",
    ext => {},
  },
  {
    in => 'from: x@y',
    rev_path => 'x@y',
    buffer => "250 ok\r\n",
    ext => {},
  },
  {
    in => 'from:<x@y> BODY=8BITMIME',
    rev_path => 'x@y',
    buffer => "250 ok\r\n",
    ext => {
      'BODY' => '8BITMIME',
    },
  },
  {
    in => 'from:<x@y> BODY=8BITMIME RANDOMEXT SIZE=10000',
    rev_path => 'x@y',
    buffer => "250 ok\r\n",
    ext => {
      'BODY' => '8BITMIME',
      'RANDOMEXT' => undef,
      'SIZE' => '10000',
    },
  },
);

foreach my $tc (@mail_from_test_cases) {
  $handle->reset_write_buffer;
  $srv->on_mail_from(sub {
    my ($s, $addr, $exts) = @_;
    
    is($addr, $tc->{rev_path}, "rev_path in callback check for '$tc->{in}'");
    cmp_deeply($exts, $tc->{ext}, "exts in callback check for '$tc->{in}'");
    
    return;
  });
  
  $sess->_mail_from_cmd('MAIL', $tc->{in});
  is($sess->transaction->reverse_path, $tc->{rev_path}, "rev_path check for '$tc->{in}'");
  is($handle->write_buffer, $tc->{buffer}, "output check for '$tc->{in}'");
}
