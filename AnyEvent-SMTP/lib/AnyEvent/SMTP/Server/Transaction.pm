package AnyEvent::SMTP::Server::Transaction;

use Mouse;

has session => (
  isa => 'AnyEvent::SMTP::Server::Session',
  is  => 'rw',
  required => 1,
);


no Mouse;
__PACKAGE__->meta->make_immutable;
