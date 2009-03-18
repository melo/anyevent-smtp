#!perl

use strict;
use warnings;
use Test::More 'no_plan';
use Test::Deep;
use AnyEvent::SMTP::Server;

my $srv = AnyEvent::SMTP::Server->new;
my $sess = AnyEvent::SMTP::Server::Session->new({
  server => $srv,
  host   => '127.0.0.1',
  port   => '1212',
});

cmp_deeply(
  [ $sess->_parse_arguments('aa  bb    dd')],
  [ 'aa', 'bb', 'dd' ],
);

cmp_deeply(
  [ $sess->_parse_arguments('aa  bb=212   dd')],
  [ 'aa', 'bb=212', 'dd' ],
);
