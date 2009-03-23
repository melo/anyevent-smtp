package AnyEvent::SMTP::Server::Request;

use Mouse;

has line => (
  isa => 'Str',
  is  => 'ro',
  required => 1,
);

has command => (
  isa => 'Str',
  is  => 'rw',
);

has args => (
  isa => 'ArrayRef',
  is  => 'ro',
  default =>  sub { [] },
);

has extensions => (
  isa => 'HashRef',
  is  => 'ro',
  default =>  sub { {} },
);

has acked_extensions => (
  isa => 'HashRef',
  is  => 'ro',
  default =>  sub { {} },
);

sub ack_extensions {
  my $self = shift;
  my ($acked, $all) = ($self->acked_extensions, $self->extensions);
  
  foreach my $ext (@_) {
    next unless exists $all->{$ext};
    $acked->{$ext} = 1;
  }
}

sub unacked_extensions {
  my ($self) = @_;
  my %exts = %{$self->extensions};
  
  foreach my $ext (keys %{$self->acked_extensions}) {
    delete $exts{$ext};
  }
  
  return keys %exts;
}

no Mouse;
__PACKAGE__->meta->make_immutable;
1;