package AnyEvent::SMTP::Server::Session;

use Mouse;
use AnyEvent::Handle;
use AnyEvent::SMTP::Server::Transaction;

# our server
has server => (
  isa => 'AnyEvent::SMTP::Server',
  is  => 'ro',
  required => 1,
);

# host/port of the peer
has host => (
  isa => 'Str',
  is  => 'ro',
  required => 1,
);

has port => (
  isa => 'Num',
  is  => 'ro',
  required => 1,
);

# extra banner stuff to send
has banner => (
  isa => 'Str',
  is  => 'rw',
);

# our internal handle for sock operations
has handle => (
  isa => 'AnyEvent::Handle',
  is  => 'rw',
  clearer => 'clear_handle',
);

# manage read queue
has is_reading => (
  isa => 'Bool',
  is  => 'rw',
  default => 0,
);

# where are we now?
has state => (
  isa => 'Str',
  is  => 'rw',
  default => 'before-banner',
);

# the current active transaction
has transaction => (
  isa     => 'AnyEvent::SMTP::Server::Transaction',
  is      => 'rw',
  lazy    => 1,
  default => sub {
    return AnyEvent::SMTP::Server::Transaction->new({ session => $_[0] })
  },
  clearer => 'reset_transaction',
);

# helo type and identification
has ehlo_type => (
  isa => 'Str',
  is  => 'rw',
);

has ehlo_host => (
  isa => 'Str',
  is  => 'rw',
);


sub start {
  my ($self, $fh) = @_;

  my $handle = AnyEvent::Handle->new(
    fh       => $fh,
    on_eof   => sub { $self->_on_disconnect(undef) },
    on_error => sub { $self->_on_disconnect($_[1]) },
  );
  $self->handle($handle);

  $self->_start_read;
  $self->_send_banner;

  return;
}


sub send {
  my $self = shift;
  my $code = shift;

  my $handle = $self->handle;
  return unless $handle;

  my $response = '';
  while (@_) {
    my $line = shift;
    $line = join(' ', @$line) if ref($line) eq 'ARRAY';
    $response .= $code . (@_? '-' : ' ') . $line . "\015\012";
  }

  $self->handle->push_write($response);
}

sub disconnect {
  my ($self, $code, @mesg) = @_;

  $self->send($code, @mesg);

  $self->handle->on_drain(sub {
    $self->clear_handle;
  });

  return;
}


##################
# Internal methods

### SMTP command parser
sub _parse_command {
  my ($self, $data) = @_;

  # detect early-talkers
  # rfc5321, 4.3.1, par 1 (SHOULD)
  if ($self->state eq 'before-banner') {
    $self->disconnect('554', 'Earlytalkers not welcome here');
    return;
  }

  # Accept \s+ with empty params, rfc5321, 4.1.1, par 1 (SHOULD)
  my ($cmd, $rest) = $data =~ /^(\w{1,12})(?:\s+(.*))?$/;
  if (!$cmd) {
    $self->send('550', 'Command not recognized');
    return;
  }

  my $ncmd = uc($cmd);
  if ($ncmd eq 'QUIT') {
    $self->disconnect('221', 'Bye');
  }
  elsif ($ncmd eq 'EHLO' || $ncmd eq 'HELO') {
    $self->_ehlo_cmd($ncmd, $rest);
  }
  elsif ($ncmd eq 'MAIL') {
    $self->_mail_from_cmd($ncmd, $rest);
  }
  else {
    $self->_err_500_command_unknown;
  }

  return;
}

sub _parse_arguments {
  my ($self, $rest) = @_;
  $rest =~ s/\s+$//;

  return split(/\s+/, $rest);
}

sub _parse_mail_address {
  my ($self, $args) = @_;
  
  my $addr = shift @$args;
  return unless $addr;
  
  # TODO: validate and canonify address
  $addr =~ s/^<(.*)>$/$1/;

  return $addr;
}

sub _parse_extensions {
  my ($self, $args) = @_;
  
  my %exts;
  foreach my $ext (@$args) {
    my ($key, $value) = $ext =~ /^([^=]+)(?:=(.+))?$/;
    return unless $key;
    $exts{$key} = $value;
  }
  
  return \%exts;
}


### SMTP Commmands
sub _ehlo_cmd {
  my ($self, $type, $rest) = @_;
  my ($host) = $self->_parse_arguments($rest);

  $self->reset_transaction;

  return $self->_err_501_syntax_error("$type requires domain/address - see rfc5321, section 4.1.1.1")
    unless $host;

  $self->ehlo_type($type);
  $self->ehlo_host($host);

  my @response = (
    '250',
    [$self->server->domain, 'Welcome,', $self->host ],
  );

  push @response, qw( PIPELINE 8BITMIME )
    if $type eq 'EHLO';

  return $self->send(@response);
}

sub _mail_from_cmd {
  my ($self, $ncmd, $rest) = @_;
  my $srv = $self->server;

  # A MAIL command starts a new transaction, rfc5321, section 4.1.1.2, para 1 
  $self->reset_transaction;

  return $self->_err_501_syntax_error('missing from') unless $rest =~ s/^from:\s*//i;
  
  my @args = $self->_parse_arguments($rest);
  my $rev_path = $self->_parse_mail_address(\@args);
  my $exts = $self->_parse_extensions(\@args);
  
  return $self->_err_501_syntax_error('invalid reverse path')
    unless defined $rev_path;
  return $self->_err_501_syntax_error('error parsing extensions')
    unless defined $exts;
  
  $self->transaction->reverse_path($rev_path);
  # TODO: mix $ext with $rev_path as soon as we get a proper ::Address object
  
  my $done;
  if (my $cb = $srv->on_mail_from) {
    $done = $cb->($self, $rev_path, $exts);
  }
  
  return if $done;
  return $self->_ok_250;
}

### OK/Error standard responses
sub _ok_250 {
  return $_[0]->send('250', 'Ok');
}

sub _err_500_command_unknown {
  return $_[0]->send('500', 'Command unrecognized');
}

sub _err_501_syntax_error {
  return $_[0]->send('501', $_[1] || 'Syntax error');
}


### Banner methods
sub _send_banner {
  my ($self) = @_;
  my $state = $self->state;

  confess("_send_banner() only valid if state is 'before-banner', current is '$state', ")
    unless $state eq 'before-banner';

  my $t; $t = AnyEvent->timer( after => 2.0, cb => sub {
    my @banner = ($self->server->domain, 'ESMTP');
    push @banner, $self->banner if $self->banner;
    $self->send(220, \@banner);
    $self->state('wait-for-ehlo');
    undef $t;
  });

  return;
}


### EOF management
sub _on_disconnect {
  my ($self) = @_;

  $self->clear_handle;
  $self->server->_on_session_ended($self);

  return;
}


### read-queue management
sub _start_read {
  my ($self) = @_;

  return unless $self->handle;
  return if $self->is_reading;
  $self->is_reading(1);

  $self->handle->push_read( line => sub {
    $self->_on_read($_[1]);
  });

  return;
}

sub _on_read {
  my ($self, $data) = @_;
  $self->is_reading(0);

  $self->_parse_command($data);

  # And keep on reading
  $self->_start_read;

  return;
}


no Mouse;
__PACKAGE__->meta->make_immutable;
