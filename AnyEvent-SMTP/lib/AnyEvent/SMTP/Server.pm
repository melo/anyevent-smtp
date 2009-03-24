package AnyEvent::SMTP::Server;

use Mouse;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::SMTP::Server::Session;
use Async::Hooks;

has 'port' => (
  isa => 'Str',
  is  => 'ro',
);

has 'current_port' => (
  isa => 'Num',
  is  => 'rw',
  clearer => 'clear_current_port',
);

has 'domain' => (
  isa      => 'Str',
  is       => 'rw',
  required => 1,
);

has 'server_guard' => (
  isa => 'Object',
  is  => 'rw',
  clearer => 'clear_server_guard',
);

has 'sessions' => (
  isa => 'HashRef',
  is  => 'ro',
  default => sub { {} },
);

has session_class => (
  isa => 'Str',
  is  => 'rw',
  default => 'AnyEvent::SMTP::Server::Session',
);

# callbacks
has on_mail_from => (
  isa => 'CodeRef',
  is  => 'rw',
);

# hooks
has hooks => (
  isa => 'Async::Hooks',
  is  => 'ro',
  default => sub { Async::Hooks->new },
  handles => [qw( call hook has_hooks_for )],
);

# Default command handler
has command_handler_class => (
  isa => 'Str',
  is  => 'rw',
  default => 'AnyEvent::SMTP::Server::Commands',
);

has command_handler => (
  isa => 'Object',
  is  => 'rw',
  lazy => 1,
  default => sub {
    my $self = shift;
    
    return $self->command_handler_class->new({ server => $self });
  },
  clearer => 'clear_command_handler',
);



sub start {
  my ($self) = @_;

  # Starts default command handler if any
  if (my $cmd_class = $self->command_handler_class) {
    # Will die if class cannot be loaded
    Mouse::load_class($cmd_class);
    $self->command_handler->start;
  }

  # Start our listening socket
  my $guard = tcp_server(
    undef,
    $self->port,
    sub { return $self->session_start(@_) },
    sub { $self->current_port($_[2]); return 0 },
  );
  $self->server_guard($guard);

  return;
}

sub stop {
  my ($self) = @_;

  $self->clear_server_guard;
  $self->clear_current_port;
  $self->clear_command_handler;

  return;
}


#################
# Session Manager

### new connection handler
sub session_start {
  my ($self, $fh, $host, $port) = @_;

  my $session = $self->session_class->new({
    server => $self,
    host   => $host,
    port   => $port,
  });
  $session->start($fh);

  $self->sessions->{$session} = $session;

  return;
}

## when a session is not longer with us
sub session_stop {
  my ($self, $session) = @_;

  return delete $self->sessions->{$session};
}


no Mouse;
__PACKAGE__->meta->make_immutable;
