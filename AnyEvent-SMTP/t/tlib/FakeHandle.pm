package FakeHandle;

use Mouse;

has write_buffer => (
  isa     => 'Str',
  is      => 'ro',
  default => '',
  clearer => 'reset_write_buffer',
);

sub push_write {
  my $self = shift;

  $self->{write_buffer} .= join('', @_);
}

no Mouse;
__PACKAGE__->meta->make_immutable;
