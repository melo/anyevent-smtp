package AnyEvent::SMTP::Server;

use Mouse;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::SMTP::Session;

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
  default  => 'example.com',
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
  default => 'AnyEvent::SMTP::Session',
);


sub start {
  my ($self) = @_;

  my $guard = tcp_server(
    undef,
    $self->port,
    sub { return $self->_on_new_connection(@_) },
    sub { $self->current_port($_[2]); return 0 },
  );

  $self->server_guard($guard);

  return;
}

sub stop {
  my ($self) = @_;

  $self->clear_server_guard;
  $self->clear_current_port;

  return;
}


##################
# Internal methods

sub _on_new_connection {
  my ($self, $fh, $host, $port) = @_;

  my $session = $self->session_class->new({
    server => $self,
    host   => $host,
    port   => $port,
    banner => $self->domain,
  });
  $session->start($fh);

  $self->sessions->{$session} = $session;

  return;
}

sub _on_session_ended {
  my ($self, $session) = @_;

  return delete $self->sessions->{$session};
}


no Mouse;
__PACKAGE__->meta->make_immutable;
