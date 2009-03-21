package AnyEvent::SMTP::Server::Session;

use Mouse;
use AnyEvent::Handle;
use AnyEvent::SMTP::Server::Transaction;

# our server
has server => (
  isa => 'AnyEvent::SMTP::Server',
  is  => 'ro',
  required => 1,
  handles => [qw( call hook parser )],
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

### SMTP Commmands
sub _ehlo_cmd {
  my ($self, $type, $rest) = @_;
  my ($host) = $self->parser->arguments($rest);

  $self->reset_transaction;

  return $self->err_501_syntax_error("$type requires domain/address - see rfc5321, section 4.1.1.1")
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

  return $self->err_501_syntax_error('missing from') unless $rest =~ s/^from:\s*//i;
  
  my @args = $self->parser->arguments($rest);
  my $rev_path = $self->parser->mail_address(\@args);
  my $exts = $self->parser->extensions(\@args);
  
  return $self->err_501_syntax_error('invalid reverse path')
    unless defined $rev_path;
  return $self->err_501_syntax_error('error parsing extensions')
    unless defined $exts;
  
  $self->transaction->reverse_path($rev_path);
  # TODO: mix $ext with $rev_path as soon as we get a proper ::Address object
  
  my $done;
  if (my $cb = $srv->on_mail_from) {
    $done = $cb->($self, $rev_path, $exts);
  }
  
  return if $done;
  return $self->ok_250;
}

### OK/Error standard responses
sub ok_250 {
  return $_[0]->send('250', $_[1] || 'ok');
}

sub err_500_command_unknown {
  return $_[0]->send('500', 'Command unknown');
}

sub err_501_syntax_error {
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
  $self->server->session_stop($self);

  return;
}


### read-queue management
sub _start_read {
  my ($self) = @_;

  return unless $self->handle;
  return if $self->is_reading;
  $self->is_reading(1);

  $self->handle->push_read( line => sub {
    $self->is_reading(0);
    $self->_line_in($_[1]);
    return $self->_start_read;
  });

  return;
}

sub _line_in {
  my ($self, $line) = @_;

  $self->call('line_in', [$self, $line], sub {
    my ($ctl, $args, $ignore_line) = @_;
    return if $ignore_line;
    
    return $self->_parse_command($args->[1]);
  });

  return $self->_start_read;
}

sub _parse_command {
  my ($self, $line) = @_;
  
  $self->call('parse_command', [$self, $line], sub {
    my ($ctl, $args, $command_parsed) = @_;
    return if $command_parsed;
    
    return $self->err_500_command_unknown;
  });
  
  return;
}


no Mouse;
__PACKAGE__->meta->make_immutable;
