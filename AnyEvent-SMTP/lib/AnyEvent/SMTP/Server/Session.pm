package AnyEvent::SMTP::Server::Session;

use Mouse;
use AnyEvent::Handle;
use AnyEvent::SMTP::Server::Transaction;
use AnyEvent::SMTP::Server::Request;
use AnyEvent::SMTP::Server::Path;
use AnyEvent::SMTP::Utils qw( split_smtp_cmd );

# our server
has server => (
  isa => 'AnyEvent::SMTP::Server',
  is  => 'ro',
  required => 1,
  handles => [qw( call hook has_hooks_for )],
);

# our helper classes
has request_class => (
  isa => 'Str',
  is  => 'rw',
  default => 'AnyEvent::SMTP::Server::Request',
);

has response_class => (
  isa => 'Str',
  is  => 'rw',
  default => 'AnyEvent::SMTP::Server::Response',
);

has path_class => (
  isa => 'Str',
  is  => 'rw',
  default => 'AnyEvent::SMTP::Server::Path',
);

has transaction_class => (
  isa => 'Str',
  is  => 'rw',
  default => 'AnyEvent::SMTP::Server::Transaction',
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
  isa        => 'AnyEvent::SMTP::Server::Transaction',
  is         => 'rw',
  lazy_build => 1,
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


### Current transaction initialization

sub _build_transaction {
  my ($self) = @_;
  
  return $self->transaction_class->new({ session => $self });
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


##################
# Internal methods

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

  my $req = $self->request_class->new({ line => $line });

  $self->call('line_in', [$self, $req, $line], sub {
    my ($ctl, $args, $ignore_line) = @_;
    return if $ignore_line;

    return $self->_parse_command($args->[1], $args->[2]);
  });

  return;
}

sub _parse_command {
  my ($self, $req, $line) = @_;

  my ($cmd, $rest) = split_smtp_cmd($line);
  return $self->err_500_command_unknown unless $cmd;

  # If no hooks are defined for parsing this cmd, then its not a
  # valid command
  my $cmd_parse_event = "parse_${cmd}_command";
  return $self->err_500_command_unknown("Unkown '$cmd'")
    unless $self->has_hooks_for($cmd_parse_event);
  
  $req->command($cmd);
  
  $self->call($cmd_parse_event, [$self, $req, $rest], sub {
    my ($ctl, $args, $is_done) = @_;
    
    # A problem was detected and already taken care off
    return if $is_done;
    print STDERR "## '$cmd_parse_event' detected no problems\n";

    # $args->[2] is $rest after crossing all handlers
    # if not empty, something was not parsed
    return $self->err_501_syntax_error("Unrecognized arguments '$rest'")
      if $args->[2];
    
    # Final global checks to command
    $self->call("validate_${cmd}_command", [$self, $req], sub {
      my ($ctl, $args, $is_error) = @_;
      return if $is_error;
      
      # Unparsed extensions must also be rejected
      if (my ($ext) = $req->unacked_extensions) {
        return $self->err_501_syntax_error("Unrecognized extension '$ext'");
      }

      # Execute it
      $self->call("execute_${cmd}_command", [$self, $req], sub {
        my ($ctl, $args, $is_done) = @_;
        return if $is_done;
        
        # Proably a better code here
        $self->err_501_syntax_error('Unhandled command');
      })
    });
  });

  return;
}


no Mouse;
__PACKAGE__->meta->make_immutable;
