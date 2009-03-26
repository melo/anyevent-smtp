package AnyEvent::SMTP::Server::Transaction;

use Mouse;

has session => (
  isa => 'AnyEvent::SMTP::Server::Session',
  is  => 'rw',
  required => 1,
);

has reverse_path => (
  isa => 'AnyEvent::SMTP::Server::Path',
  is  => 'rw',
);

has forward_paths => (
  isa => 'ArrayRef',
  is  => 'ro',
  default => sub { [] },
);

no Mouse;
__PACKAGE__->meta->make_immutable;
