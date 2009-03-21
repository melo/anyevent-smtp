#!perl

use strict;
use warnings;
use Test::More 'no_plan';
use Test::Deep;
use AnyEvent::SMTP::Utils qw( :all );

### test split_smtp_cmd
my @cmd_splitter_tcs = (
  {
    in  => 'EHLO me',
    out => [ 'ehlo', 'me', 'EHLO' ],
  },
  {
    in  => 'helo me',
    out => [ 'helo', 'me', 'helo' ],
  },
  {
    in => 'MAIL from:<xpto@ypto>',
    out => [ 'mail', 'from:<xpto@ypto>', 'MAIL' ],
  },
  {
    in => 'MAIL from:<xpto@ypto>  BODY=8BITMIME  SIZE=1000',
    out => [ 'mail', 'from:<xpto@ypto>  BODY=8BITMIME  SIZE=1000', 'MAIL' ],
  },
  {
    in => 'QuiT',
    out => [ 'quit', '', 'QuiT' ],
  },
  {
    in => 'QuIt   ',
    out => [ 'quit', '', 'QuIt' ],
  },
  {
    in => '123456789123456789 ',
    out => [],
  },
  {
    in => '  MAIL from:<xpto@ypto>  ',
    out => [],
  },
);

foreach my $tc (@cmd_splitter_tcs) {
  cmp_deeply(
    [ split_smtp_cmd($tc->{in}) ],
    $tc->{out},
    "splitted cmd '$tc->{in}' properly",
  );
}


### test split_smtp_cmd_args
my @cmd_args_splitter_tcs = (
  { in => 'aa  bb    dd',      out => [ 'aa', 'bb', 'dd' ],      },
  { in => 'aa  bb=1121    dd', out => [ 'aa', 'bb=1121', 'dd' ], },
  { in => '  aa  bb=1121  dd', out => [ 'aa', 'bb=1121', 'dd' ], },
  { in => 'aa  bb=1121  dd  ', out => [ 'aa', 'bb=1121', 'dd' ], },
  { in => ' aa  bb=1121  dd ', out => [ 'aa', 'bb=1121', 'dd' ], },
);

foreach my $tc (@cmd_args_splitter_tcs) {
  cmp_deeply(
    [ split_smtp_cmd_args($tc->{in}) ],
    $tc->{out},
    "splitted args '$tc->{in}' properly",
  );
}


### test address parser for MAIL FROM and RCPT TO
my @mail_addr_test_cases = (
  { in => '<>',    out => ''    },
  { in => 'x@y',   out => 'x@y' },
  { in => '<x@y>', out => 'x@y' },
);

foreach my $tc (@mail_addr_test_cases) {
  is(
    parse_smtp_cmd_mail_addr($tc->{in}),
    $tc->{out},
    "parsed addr '$tc->{in}' properly => '$tc->{out}'",
  );
}


### test SMTP extensions parser for MAIL FROM and RCPT TO
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
  my @args = split_smtp_cmd_args($tc->{in});
  cmp_deeply(
    \@args,
    $tc->{args},
    "splitted args '$tc->{in}' properly",
  );
  cmp_deeply(
    parse_smtp_cmd_extensions(@args),
    $tc->{out},
    "extension parser for '$tc->{in}'",
  );
}
