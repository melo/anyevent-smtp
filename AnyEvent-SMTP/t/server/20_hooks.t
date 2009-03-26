#!perl

use strict;
use warnings;
use lib './t/tlib';
use Test::More 'no_plan';
use Test::Deep;
use AnyEvent::SMTP::Server;
use AnyEvent::SMTP::Server::Commands;
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

# Make sure all of ::Commands are set and ready to go
$srv->command_handler->start;

# Mock the handle and restart the session read queue
my $handle = FakeHandle->new;
$sess->{handle} = $handle; # Bypass Mouse checks
$sess->is_reading(0);
$sess->_start_read;


### check line_in and parse_*_command chains
$srv->hook('line_in', sub {
  my ($ctl, $args) = @_;
  my ($session, $req, $line) = @$args;
  isa_ok($session, 'AnyEvent::SMTP::Server::Session');
  isa_ok($req, 'AnyEvent::SMTP::Server::Request');

  $called{'line_in'}++;

  $called{'line_in_out'} = 'done';
  return $ctl->done if $line =~ m/^ignore /;

  $called{'line_in_out'} = 'declined';
  return $ctl->declined;
});

$srv->hook('parse_xpto_command', sub {
  my ($ctl, $args) = @_;
  my ($session, $req, $rest) = @$args;
  isa_ok($session, 'AnyEvent::SMTP::Server::Session');
  isa_ok($req, 'AnyEvent::SMTP::Server::Request');
  is($req->command, 'xpto');
  
  $called{'xpto_in'}++;

  if ($rest =~ m/^done\s+(\w+)$/) {
    $called{'xpto_out'} = 'done';
    $session->ok_250("OK [$1]");
    return $ctl->done;
  }

  if ($rest =~ m/^unparsed\b/) {
    $called{'xpto_out'} = 'unparsed';
    return $ctl->declined;
  }

  return $ctl->next;
});

# make sure xpto command exists
$srv->hook('execute_xpto_command', sub {});


### Support two MAIL FROM extensions, RANDOMEXT and SIZE
$srv->hook('validate_mail_command', sub {
  my ($ctl, $args) = @_;
  my ($sess, $req) = @$args;
  
  $req->ack_extensions(qw( RANDOMEXT SIZE ));
  
  return $ctl->next;
});


### Support two RCPT TO extensions, NICEEEE
$srv->hook('validate_rcpt_command', sub {
  my ($ctl, $args) = @_;
  my ($sess, $req) = @$args;
  
  $req->ack_extensions(qw( NICEEEE GOOOD ));
  
  return $ctl->next;
});


### Support RCPT checks for domains

$srv->hook('check_rcpt_address', sub {
  my ($ctl, $args) = @_;
  my ($sess, $req) = @$args;
  my $addr = $req->args->[0];
  
  # Accept only mails from cool.domain domain
  return $ctl->done if $addr && $addr =~ m/\@cool.domain$/;
  
  return $ctl->next;
});


### Our test cases
my @htcs = (
  ### IGNORE - test line_in stuff
  {
    test => 'tc-1',
    item => 'ignore me',
    desc => 'ignore input lines works',
    hooks_called => {
      line_in => 1, line_in_out => 'done',
    },
    buffer => '',
  },
  
  ### KILL - test command unknown
  {
    test => 'tc-2',
    item => 'kill me',
    desc => 'test with unkown command, declined ok',
    hooks_called => {
      line_in => 1, line_in_out => 'declined',
    },
    buffer => "500 Command unknown\r\n",
  },

  ### XPTO - our test command
  {
    test => 'tc-3',
    item => 'xpto done yuppii',
    desc => 'parse_xpto_command with proprietary parsing, ok',
    hooks_called => {
      line_in => 1, line_in_out => 'declined',
      xpto_in => 1, xpto_out    => 'done',
    },
    buffer => "250 OK [yuppii]\r\n",
  },

  {
    test => 'tc-4',
    item => 'xpto unparsed stuff',
    desc => 'parse_xpto_command didnt parse it, unkown',
    hooks_called => {
      line_in => 1, line_in_out => 'declined',
      xpto_in => 1, xpto_out    => 'unparsed',
    },
    buffer => "501 Unrecognized arguments 'unparsed stuff'\r\n",
  },
  
  ### HELO
  {
    test => 'tc-5',
    item => 'helo',
    buffer => "501 helo requires domain/address - see rfc5321, section 4.1.1.1\r\n",
  },
  
  {
    test => 'tc-6',
    item => 'helo domain.me wtf',
    buffer => "250 example.com Welcome, domain.me\r\n",
  },
  
  {
    test => 'tc-7',
    item => 'helo domain.me',
    buffer => "250 example.com Welcome, domain.me\r\n",
    tests => sub {
      is($sess->ehlo_type, 'helo');
      is($sess->ehlo_host, 'domain.me');
    },
  },
   
  ### EHLO
  {
    test => 'tc-8',
    item => 'ehlo',
    buffer => "501 ehlo requires domain/address - see rfc5321, section 4.1.1.1\r\n",
  },
  
  {
    test => 'tc-9',
    item => 'ehlo domain.me wtf',
    buffer => "250-example.com Welcome, domain.me\r\n250 8BITMIME\r\n",
  },
  
  {
    test => 'tc-10',
    item => 'ehlo domain.me',
    buffer => "250-example.com Welcome, domain.me\r\n250 8BITMIME\r\n",
    tests => sub {
      is($sess->ehlo_type, 'ehlo');
      is($sess->ehlo_host, 'domain.me');
    },
  },
  
  ### MAIL
  {
    test => 'tc-11',
    item => 'mail',
    buffer => "501 Missing 'from:' argument\r\n",
  },
  
  {
    test => 'tc-12',
    item => 'mail from:',
    buffer => "501 Missing address\r\n",
  },
  
  {
    test => 'tc-13',
    item => 'mail from:<xpto@me> =',
    buffer => "501 Unable to parse '='\r\n",
  },
  
  {
    test => 'tc-14',
    item => 'mail from:<xpto@me> BODY=8BITMIME WTF',
    buffer => "501 Unrecognized extension 'WTF'\r\n",
  },
  
  {
    test => 'tc-15',
    item => 'mail from:<xpto@me> BODY=8BITMIME',
    tests => sub {
      my $r = $sess->transaction->reverse_path;
      is($r->addr, 'xpto@me');
      cmp_deeply($r->extensions, {
        'BODY' => '8BITMIME',
      });
    },
  },
  
  {
    test => 'tc-16',
    item => 'mail from:<>',
    tests => sub {
      my $r = $sess->transaction->reverse_path;
      is($r->addr, '');
      cmp_deeply($r->extensions, {});
    },
  },
  
  {
    test => 'tc-17',
    item => 'mail from:<x@y>',
    tests => sub {
      my $r = $sess->transaction->reverse_path;
      is($r->addr, 'x@y');
      cmp_deeply($r->extensions, {});
    },
  },
  
  {
    test => 'tc-18',
    item => 'mail from: <x@y>',
    tests => sub {
      my $r = $sess->transaction->reverse_path;
      is($r->addr, 'x@y');
      cmp_deeply($r->extensions, {});
    },
  },
  
  {
    test => 'tc-19',
    item => 'mail from:x@y',
    tests => sub {
      my $r = $sess->transaction->reverse_path;
      is($r->addr, 'x@y');
      cmp_deeply($r->extensions, {});
    },
  },
  
  {
    test => 'tc-20',
    item => 'mail from: x@y',
    tests => sub {
      my $r = $sess->transaction->reverse_path;
      is($r->addr, 'x@y');
      cmp_deeply($r->extensions, {});
    },
  },
  
  {
    test => 'tc-21',
    item => 'mail from:<xpto@me> BODY=8BITMIME RANDOMEXT SIZE=10000',
    tests => sub {
      my $r = $sess->transaction->reverse_path;
      is($r->addr, 'xpto@me');
      cmp_deeply($r->extensions, {
        'BODY' => '8BITMIME',
        'RANDOMEXT' => undef,
        'SIZE' => '10000',
      });
    },
  },
  
  ### RCPT
  {
    test => 'tc-22',
    item => ['mail from:<>', 'rcpt'],
    buffer => "250 ok\r\n501 Missing 'TO:' argument\r\n",
  },
  
  {
    test => 'tc-23',
    item => ['mail from:<>', 'rcpt to:'],
    buffer => "250 ok\r\n501 Missing address\r\n",
  },
  
  {
    test => 'tc-24',
    item => ['mail from:<>', 'rcpt to:<xpto@cool.domain> ='],
    buffer => "250 ok\r\n501 Unable to parse '='\r\n",
  },
  
  {
    test => 'tc-25',
    item => ['mail from:<>', 'rcpt to:<xpto@cool.domain> BODY=8BITMIME'],
    buffer => "250 ok\r\n501 Unrecognized extension 'BODY'\r\n",
  },
  
  {
    test => 'tc-26',
    item => ['mail from:<>', 'rcpt to:<xpto@cool.domain>'],
    buffer => "250 ok\r\n250 ok\r\n",
    tests => sub {
      my $r = $sess->transaction->forward_paths;
      is($r->[0]->addr, 'xpto@cool.domain');
      cmp_deeply($r->[0]->extensions, {});
    },
  },
  
  {
    # FIXME: a reverse path is mandatory!
    test => 'tc-27',
    item => ['mail from:<>', 'rcpt to:<>'],
    buffer => "250 ok\r\n553 Action not taken: mailbox name not allowed\r\n",
    tests => sub {
      my $r = $sess->transaction->forward_paths;
      is(scalar(@$r), 0);
    },
  },
  
  {
    test => 'tc-28',
    item => ['mail from:<>', 'rcpt to:<x@cool.domain>'],
    buffer => "250 ok\r\n250 ok\r\n",
    tests => sub {
      my $r = $sess->transaction->forward_paths;
      is($r->[0]->addr, 'x@cool.domain');
      cmp_deeply($r->[0]->extensions, {});
    },
  },
  
  {
    test => 'tc-29',
    item => ['mail from:<>', 'rcpt to: <x@cool.domain>'],
    buffer => "250 ok\r\n250 ok\r\n",
    tests => sub {
      my $r = $sess->transaction->forward_paths;
      is($r->[0]->addr, 'x@cool.domain');
      cmp_deeply($r->[0]->extensions, {});
    },
  },
  
  {
    test => 'tc-30',
    item => ['mail from:<>', 'rcpt to:x@cool.domain'],
    buffer => "250 ok\r\n250 ok\r\n",
    tests => sub {
      my $r = $sess->transaction->forward_paths;
      is($r->[0]->addr, 'x@cool.domain');
      cmp_deeply($r->[0]->extensions, {});
    },
  },
  
  {
    test => 'tc-31',
    item => ['mail from:<>', 'rcpt to: x@cool.domain'],
    buffer => "250 ok\r\n250 ok\r\n",
    tests => sub {
      my $r = $sess->transaction->forward_paths;
      is($r->[0]->addr, 'x@cool.domain');
      cmp_deeply($r->[0]->extensions, {});
    },
  },
  
  {
    test => 'tc-32',
    item => ['mail from:<>', 'rcpt to:<xpto@cool.domain> GOOOD=me NICEEEE '],
    buffer => "250 ok\r\n250 ok\r\n",
    tests => sub {
      my $r = $sess->transaction->forward_paths;
      is($r->[0]->addr, 'xpto@cool.domain');
      cmp_deeply($r->[0]->extensions, {
        'NICEEEE' => undef,
        'GOOOD'   => 'me'
      });
    },
  },
  
  {
    test => 'tc-33',
    item => ['mail from:<>', 'rcpt to:<xpto@no.domain> GOOOD=me NICEEEE '],
    buffer => "250 ok\r\n553 Action not taken: mailbox name not allowed\r\n",
    tests => sub {
      my $r = $sess->transaction->forward_paths;
      is(scalar(@$r), 0);
    },
  },
  
  ### QUIT
  {
    test => 'tc-34',
    item => 'quit yeah',
    buffer => "501 Unrecognized arguments 'yeah'\r\n",
  },
  
  {
    test => 'tc-35',
    item => 'quit',
    buffer => "221 Bye now\r\n",
  },
  
  ### NOOP
  {
    test => 'tc-36',
    item => 'noop yeah',
    buffer => "250 ok\r\n",
  },
  
  {
    test => 'tc-37',
    item => 'noop',
    buffer => "250 ok\r\n",
  },
);

foreach my $tc (@htcs) {
  $sess->clear_transaction;
  $handle->reset_write_buffer;
  %called = ();
  $handle->push_item($tc->{item});
  if (exists $tc->{hooks_called}) {
    cmp_deeply(
      \%called,
      $tc->{hooks_called},
      "$tc->{desc} [$tc->{test}]",
    );
  }

  is($handle->write_buffer, $tc->{buffer}, "correct output [$tc->{test}]")
    if exists $tc->{buffer};

  $tc->{tests}->($tc->{test}) if exists $tc->{tests};
}
