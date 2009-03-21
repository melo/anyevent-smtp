package AnyEvent::SMTP::Server::Parser;

use Mouse;

has server => (
  isa => 'AnyEvent::SMTP::Server',
  is  => 'ro',
  required => 1,
);

### SMTP command parser
sub command {
  my ($self, $data) = @_;

  # detect early-talkers
  # rfc5321, 4.3.1, par 1 (SHOULD)
  if ($self->state eq 'before-banner') {
    $self->disconnect('554', 'Earlytalkers not welcome here');
    return;
  }

  # Accept \s+ with empty params, rfc5321, 4.1.1, par 1 (SHOULD)
  my ($cmd, $rest) = $data =~ /^(\w{1,12})(?:\s+(.*))?$/;
  if (!$cmd) {
    $self->send('550', 'Command not recognized');
    return;
  }

  my $ncmd = uc($cmd);
  if ($ncmd eq 'QUIT') {
    $self->disconnect('221', 'Bye');
  }
  elsif ($ncmd eq 'EHLO' || $ncmd eq 'HELO') {
    $self->_ehlo_cmd($ncmd, $rest);
  }
  elsif ($ncmd eq 'MAIL') {
    $self->_mail_from_cmd($ncmd, $rest);
  }
  else {
    $self->_err_500_command_unknown;
  }

  return;
}

sub arguments {
  my ($self, $rest) = @_;
  $rest =~ s/\s+$//;

  return split(/\s+/, $rest);
}

sub mail_address {
  my ($self, $args) = @_;
  
  my $addr = shift @$args;
  return unless $addr;
  
  # TODO: validate and canonify address
  $addr =~ s/^<(.*)>$/$1/;

  return $addr;
}

sub extensions {
  my ($self, $args) = @_;
  
  my %exts;
  foreach my $ext (@$args) {
    my ($key, $value) = $ext =~ /^([^=]+)(?:=(.+))?$/;
    return unless $key;
    $exts{$key} = $value;
  }
  
  return \%exts;
}

1;