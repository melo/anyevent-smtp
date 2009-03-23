#!perl

use strict;
use warnings;
use Test::More 'no_plan';
use Test::Deep;

use AnyEvent::SMTP::Server::Request;

my $req = AnyEvent::SMTP::Server::Request->new({
  line => 'MAIL FROM:<melo@domain.com> BODY=8BITMIME COOL LOVELLY=YES BITE=ME',
  command => 'mail',
  args => [
    'melo@domain.com',
    'BODY=8BITMIME',
    'COOL',
    'LOVELLY=YES',
    'BITE=ME',
  ],
  extensions => {
    'BODY'    => '8BITMIME',
    'COOL'    => undef,
    'LOVELLY' => 'YES',
    'BITE'    => 'ME',
  },
});

ok($req);
is(
  $req->line,
  'MAIL FROM:<melo@domain.com> BODY=8BITMIME COOL LOVELLY=YES BITE=ME',
);
is($req->command, 'mail');
cmp_deeply(
  $req->args,
  ['melo@domain.com', 'BODY=8BITMIME', 'COOL', 'LOVELLY=YES', 'BITE=ME'],
);
cmp_deeply(
  $req->extensions,
  {
    'BODY'    => '8BITMIME',
    'COOL'    => undef,
    'LOVELLY' => 'YES',
    'BITE'    => 'ME',
  },
);
cmp_deeply($req->acked_extensions, {});

$req->ack_extensions(qw( BODY XPTO COOL ));
cmp_deeply($req->acked_extensions, {
  'BODY' => 1,
  'COOL' => 1,
});

is(scalar($req->unacked_extensions), 2);
cmp_deeply(
  [ sort $req->unacked_extensions ],
  [ 'BITE', 'LOVELLY' ],
);

$req->ack_extensions(qw( LOVELLY BITE BODY COOL YPTO ));
cmp_deeply($req->acked_extensions, {
  'BODY'    => 1,
  'COOL'    => 1,
  'BITE'    => 1,
  'LOVELLY' => 1,
});

is(scalar($req->unacked_extensions), 0);
cmp_deeply(
  [ $req->unacked_extensions ],
  [ ],
);
