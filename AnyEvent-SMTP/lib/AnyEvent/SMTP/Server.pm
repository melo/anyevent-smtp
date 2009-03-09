package AnyEvent::SMTP::Server;

use Mouse;
use AnyEvent;
use AnyEvent::Socket;

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



sub start {
  my ($self) = @_;

  my $guard = tcp_server(
    undef,
    $self->port,
    sub {  },
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


no Mouse;
__PACKAGE__->meta->make_immutable;
