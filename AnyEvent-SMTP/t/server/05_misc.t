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


# test address parser for MAIL FROM and RCPT TO
my @mail_addr_test_cases = (
  { in => '<>',    out => ''    },
  { in => 'x@y',   out => 'x@y' },
  { in => '<x@y>', out => 'x@y' },
);

foreach my $tc (@mail_addr_test_cases) {
  is($sess->_parse_mail_address([$tc->{in}]), $tc->{out});
}

# test SMTP extensions parser for MAIL FROM and RCPT TO
my @extenions_test_cases = (
  {
    in => 'BODY=8BITMIME',
    args => [ 'BODY=8BITMIME' ],
    out => {
      'BODY' => '8BITMIME',
    },
  },
  {
    in => 'BODY=8BITMIME XPTO',
    args => [ 'BODY=8BITMIME', 'XPTO' ],
    out => {
      'BODY' => '8BITMIME',
      'XPTO' => undef,
    },
  },
  {
    in => 'XPTO  BODY=8BITMIME  YPTO=SOME',
    args => [ 'XPTO', 'BODY=8BITMIME', 'YPTO=SOME' ],
    out => {
      'BODY' => '8BITMIME',
      'XPTO' => undef,
      'YPTO' => 'SOME',
    },
  },
);

foreach my $tc (@extenions_test_cases) {
  my @args = $sess->_parse_arguments($tc->{in});
  cmp_deeply(
    \@args,
    $tc->{args},
  );
  cmp_deeply(
    $sess->_parse_extensions(\@args),
    $tc->{out},
    "extension parser for '$tc->{in}'",
  );
}

### Support for the new Async::Hooks support
isa_ok($srv->hooks, 'Async::Hooks');
can_ok($srv, qw( call hook ));

my $test_hook_srv  = 0;
my $test_hook_sess = 0;
$srv->hook('test', sub {
  my ($ctl) = @_;
  $test_hook_srv++;
  $ctl->next;
});
$sess->hook('test', sub {
  my ($ctl) = @_;
  $test_hook_sess++;
  $ctl->next;
});

$srv->call('test');
is($test_hook_srv,  1);
is($test_hook_sess, 1);

$sess->call('test');
is($test_hook_srv,  2);
is($test_hook_sess, 2);


### Parser support
can_ok($srv, qw( parser_class parser ));
my $parser = $srv->parser;
can_ok($parser, qw( server ));
