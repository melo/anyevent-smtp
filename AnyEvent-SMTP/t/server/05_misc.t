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
