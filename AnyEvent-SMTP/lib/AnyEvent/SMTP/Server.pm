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
);

has 'domain' => (
  isa      => 'Str',
  is       => 'rw',
  required => 1,
  default  => 'example.com',
);



no Mouse;
__PACKAGE__->meta->make_immutable;
