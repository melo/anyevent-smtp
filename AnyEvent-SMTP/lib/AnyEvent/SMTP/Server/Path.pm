package AnyEvent::SMTP::Server::Path;

use Mouse;

has addr => (
  isa => 'Str',
  is  => 'ro',
);

has extensions => (
  isa => 'HashRef',
  is  => 'ro',
  default =>  sub { {} },
);

no Mouse;
__PACKAGE__->meta->make_immutable;
1;