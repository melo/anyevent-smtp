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


### Support two MAIL FROM extensions, RANDOMEXT and SIZE
$srv->hook('validate_mail_command', sub {
  my ($ctl, $args) = @_;
  my ($sess, $req) = @$args;
  
  $req->ack_extensions(qw( RANDOMEXT SIZE ));
  
  return $ctl->next;
});


### Our test cases
my @htcs = (
  ### IGNORE - test line_in stuff
  {
    item => 'ignore me',
    desc => 'ignore input lines works',
    hooks_called => {
      line_in => 1, line_in_out => 'done',
    },
    buffer => '',
  },
  
  ### KILL - test command unknown
  {
    item => 'kill me',
    desc => 'test with unkown command, declined ok',
    hooks_called => {
      line_in => 1, line_in_out => 'declined',
    },
    buffer => "500 Command unknown\r\n",
  },

  ### XPTO - our test command
  {
    item => 'xpto done yuppii',
    desc => 'parse_xpto_command with proprietary parsing, ok',
    hooks_called => {
      line_in => 1, line_in_out => 'declined',
      xpto_in => 1, xpto_out    => 'done',
    },
    buffer => "250 OK [yuppii]\r\n",
  },

  {
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
    item => 'helo',
    buffer => "501 helo requires domain/address - see rfc5321, section 4.1.1.1\r\n",
  },
  
  {
    item => 'helo domain.me wtf',
    buffer => "501 arguments after host 'domain.me' not permitted\r\n",
  },
  
  {
    item => 'helo domain.me',
    buffer => "250 example.com Welcome, domain.me\r\n",
    tests => sub {
      is($sess->ehlo_type, 'helo');
      is($sess->ehlo_host, 'domain.me');
    },
  },
   
  ### EHLO
  {
    item => 'ehlo',
    buffer => "501 ehlo requires domain/address - see rfc5321, section 4.1.1.1\r\n",
  },
  
  {
    item => 'ehlo domain.me wtf',
    buffer => "501 arguments after host 'domain.me' not permitted\r\n",
  },
  
  {
    item => 'ehlo domain.me',
    buffer => "250-example.com Welcome, domain.me\r\n250 8BITMIME\r\n",
    tests => sub {
      is($sess->ehlo_type, 'ehlo');
      is($sess->ehlo_host, 'domain.me');
    },
  },
  
  ### MAIL
  {
    item => 'mail',
    buffer => "501 Missing 'from:' argument\r\n",
  },
  
  {
    item => 'mail from:',
    buffer => "501 Missing reverse-path after FROM:\r\n",
  },
  
  {
    item => 'mail from:<xpto@me> =',
    buffer => "501 Unable to parse '='\r\n",
  },
  
  {
    item => 'mail from:<xpto@me> BODY=8BITMIME WTF',
    buffer => "501 Unrecognized extension 'WTF'\r\n",
  },
  
  {
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
    item => 'mail from:<>',
    tests => sub {
      my $r = $sess->transaction->reverse_path;
      is($r->addr, '');
      cmp_deeply($r->extensions, {});
    },
  },
  
  {
    item => 'mail from:<x@y>',
    tests => sub {
      my $r = $sess->transaction->reverse_path;
      is($r->addr, 'x@y');
      cmp_deeply($r->extensions, {});
    },
  },
  
  {
    item => 'mail from: <x@y>',
    tests => sub {
      my $r = $sess->transaction->reverse_path;
      is($r->addr, 'x@y');
      cmp_deeply($r->extensions, {});
    },
  },
  
  {
    item => 'mail from:x@y',
    tests => sub {
      my $r = $sess->transaction->reverse_path;
      is($r->addr, 'x@y');
      cmp_deeply($r->extensions, {});
    },
  },
  
  {
    item => 'mail from: x@y',
    tests => sub {
      my $r = $sess->transaction->reverse_path;
      is($r->addr, 'x@y');
      cmp_deeply($r->extensions, {});
    },
  },
  
  {
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
);

foreach my $tc (@htcs) {
  $handle->reset_write_buffer;
  %called = ();
  $handle->push_item($tc->{item});
  if (exists $tc->{hooks_called}) {
    cmp_deeply(
      \%called,
      $tc->{hooks_called},
      $tc->{desc},
    );
  }

  if (exists $tc->{buffer}) { is($handle->write_buffer, $tc->{buffer}) }
  else                      { is($handle->write_buffer, "250 ok\r\n")  }

  $tc->{tests}->() if exists $tc->{tests};
}
