package AnyEvent::SMTP::Session;

use Mouse;
use AnyEvent::Handle;


has server => (
  isa => 'AnyEvent::SMTP::Server',
  is  => 'ro',  
  required => 1,
);

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

has banner => (
  isa => 'Str',
  is  => 'rw',  
  required => 1,
);


no Mouse;
__PACKAGE__->meta->make_immutable;
