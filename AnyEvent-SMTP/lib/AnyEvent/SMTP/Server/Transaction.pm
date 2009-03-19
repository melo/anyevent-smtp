package AnyEvent::SMTP::Server::Transaction;

use Mouse;

has session => (
  isa => 'AnyEvent::SMTP::Server::Session',
  is  => 'rw',
  required => 1,
);

has reverse_path => (
  isa => 'Str',
  is  => 'rw',
);

no Mouse;
__PACKAGE__->meta->make_immutable;
