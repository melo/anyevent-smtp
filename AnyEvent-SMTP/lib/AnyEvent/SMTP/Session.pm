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

has is_reading => (
  isa => 'Bool',
  is  => 'rw',  
  default => 0,
);



sub start {
  my ($self, $fh) = @_;

  my $handle = AnyEvent::Handle->new(
    fh       => $fh,
    on_eof   => sub { $self->_on_disconnect(undef) },
    on_error => sub { $self->_on_disconnect($_[1]) },
  );
  $self->handle($handle);

  $self->_start_read;  
  $self->_send_banner;
  
  return;
}


sub send {
  my $self = shift;
  my $code = shift;
  my $mesg = join(' ', $code, @_);
  
  $self->handle->push_write($mesg."\015\012");
}


##################
# Internal methods

sub _send_banner {
  my ($self) = @_;
  
  $self->send(220, $self->banner, 'ESMTP');

  return;
}


sub _on_disconnect {
  my ($self) = @_;
  
  $self->clear_handle;
  $self->server->_on_session_ended($self);
  
  return;
}

sub _start_read {
  my ($self) = @_;
  
  return if $self->is_reading;
  $self->is_reading(1);
  
  $self->handle->push_read( line => sub {
    $self->_on_read($_[1]);
  });

  return;
}


sub _on_read {
  my ($self, $data) = @_;
  $self->is_reading(0);
  
  # Process $data...
  
  # And keep on reading
  $self->_start_read;
  
  return;
}


no Mouse;
__PACKAGE__->meta->make_immutable;
