package FakeHandle;

use Mouse;

has write_buffer => (
  isa     => 'Str',
  is      => 'ro',
  default => '',
  lazy    => 1,
  clearer => 'reset_write_buffer',
);

has read_buffer => (
  isa => 'ArrayRef',
  is  => 'ro',
  default => sub { [] },
);

has pending_reads => (
  isa => 'ArrayRef',
  is => 'ro',
  default => sub { [] },
);


sub push_write {
  my $self = shift;

  $self->{write_buffer} .= join('', @_);
}

sub push_read {
  my ($self, $type, $cb) = @_;

  confess("FakeHandle only supports push_read of type 'line'")
    unless $type eq 'line';

  my $rbuf = $self->read_buffer;
  if (@$rbuf) {
    $cb->($self, shift @$rbuf);
  }
  else {
    push @{$self->pending_reads}, $cb;
  }

  return;
}

sub push_item {
  my ($self, $item) = @_;
  my $rbuf = $self->read_buffer;
  my $pbuf = $self->pending_reads;

  push @$rbuf, (ref($item) eq 'ARRAY'? @$item : $item);
  
  return unless @$pbuf;
  
  while (@$rbuf && @$pbuf) {
    shift(@$pbuf)->($self, shift @$rbuf);
  }
  
  return;
}


no Mouse;
__PACKAGE__->meta->make_immutable;
