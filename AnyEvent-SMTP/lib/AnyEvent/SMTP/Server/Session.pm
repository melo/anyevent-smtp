package AnyEvent::SMTP::Server::Session;

use Mouse;
use AnyEvent::Handle;


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
  required => 1,
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
  else {
    $self->send('550', 'Command not recognized');
  }

  return;
}


### Banner methods
sub _send_banner {
  my ($self) = @_;
  my $state = $self->state;

  confess("_send_banner() only valid if state is 'before-banner', current is '$state', ")
    unless $state eq 'before-banner';

  my $t; $t = AnyEvent->timer( after => 2.0, cb => sub {
    $self->send(220, [$self->server->domain, 'ESMTP', $self->banner]);
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
