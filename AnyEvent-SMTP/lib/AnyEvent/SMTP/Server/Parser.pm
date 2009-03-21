package AnyEvent::SMTP::Server::Parser;

use Mouse;

has server => (
  isa => 'AnyEvent::SMTP::Server',
  is  => 'ro',
  required => 1,
);

1;