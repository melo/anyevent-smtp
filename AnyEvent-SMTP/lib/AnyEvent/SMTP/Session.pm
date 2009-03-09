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

has handle => (
  isa => 'AnyEvent::Handle',
  is  => 'rw',
  clearer => 'clear_handle',
);


sub start {
  my ($self, $fh) = @_;

  my $handle = AnyEvent::Handle->new(
    fh       => $fh,
    on_eof   => sub { $self->_on_disconnect(undef) },
    on_error => sub { $self->_on_disconnect($_[1]) },
  );
  $self->handle($handle);
  
  $handle->push_read(line => sub { });
  
  return;
}


##################
# Internal methods

sub _on_disconnect {
  my ($self) = @_;
  
  $self->clear_handle;
  $self->server->_on_session_ended($self);
  
  return;
}


no Mouse;
__PACKAGE__->meta->make_immutable;
