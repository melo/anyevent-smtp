package AnyEvent::SMTP::Server::Commands;

use Mouse;
use AnyEvent::SMTP::Utils qw( :all );

##############
# Object slots

has server => (
  isa => 'AnyEvent::SMTP::Server',
  is  => 'ro',  
  required => 1,
  handles => [qw( call hook has_hooks_for )],
);


################
# Initialization

sub start {
  my ($self) = @_;

  $self->hook('parse_helo_command',   \&_parse_ehlo_command);
  $self->hook('execute_helo_command', \&_exec_ehlo_command );
  
  $self->hook('parse_ehlo_command',   \&_parse_ehlo_command);
  $self->hook('execute_ehlo_command', \&_exec_ehlo_command );
  
  $self->hook('parse_mail_command',    \&_parse_mail_command   );
  $self->hook('validate_mail_command', \&_validate_mail_command);
  $self->hook('execute_mail_command',  \&_exec_mail_command    );
  
  return;
}


###############
# SMTP commands

### EHLO/HELO
sub _parse_ehlo_command {
  my ($ctl, $args) = @_;
  my ($sess, $req, $rest) = @$args;
  my $cmd = $req->command;

  $sess->clear_transaction;
  
  my ($host, @other) = split_smtp_cmd_args($rest);
  if (@other) {
    $sess->err_501_syntax_error("arguments after host '$host' not permitted");
    return $ctl->done;
  }

  if (!$host) {
    $sess->err_501_syntax_error("$cmd requires domain/address - see rfc5321, section 4.1.1.1");
    return $ctl->done;
  }

  $sess->ehlo_type($cmd);
  $sess->ehlo_host($host);

  # Clear $rest, all parsed  
  $args->[2] = '';
  
  $ctl->next;
}

sub _exec_ehlo_command {
  my ($ctl, $args) = @_;
  my ($sess, $req, $rest) = @$args;

  my @response = (
    '250',
    [ $sess->server->domain, 'Welcome,', $sess->ehlo_host ],
  );

  push @response, qw( 8BITMIME )
    if $sess->ehlo_type eq 'ehlo';

  $sess->send(@response);
  return $ctl->done;
}


### MAIL FROM:<address> (EXT(=VALUE)?)*
sub _parse_mail_command {
  my ($ctl, $args) = @_;
  my ($sess, $req, $rest) = @$args;

  # A MAIL command starts a new transaction, rfc5321, section 4.1.1.2, para 1 
  $sess->clear_transaction;

  # Make sure we have our mandatory first argument  
  unless ($rest =~ s/^from:\s*//i) {
    $sess->err_501_syntax_error("Missing 'from:' argument");
    return $ctl->done;
  }
  
  # Mark $rest as parsed, we'll take care of the rest now
  my ($addr, @exts) = split_smtp_cmd_args($rest);
  $args->[2] = '';
  
  # parse and validate reverse-path, store it in request args
  $addr = parse_smtp_cmd_mail_addr($addr);
  if (!defined $addr) {
    $sess->err_501_syntax_error('Missing reverse-path after FROM:');
    return $ctl->done;
  }
  push @{$req->args}, $addr;
  
  # Parse extenions and store them in our request
  my $exts = parse_smtp_cmd_extensions(@exts);
  if (!$exts) {
    $sess->err_501_syntax_error("Unable to parse '".join(' ', @exts)."'");
    return $ctl->done;
  }
  elsif (%$exts) {
    %{$req->extensions} = %$exts;
  }
  else {
    # nothing to do, no extensions detected
  }
  
  return $ctl->next;
}

sub _validate_mail_command {
  my ($ctl, $args) = @_;
  my ($sess, $req) = @$args;
  
  # We know how to deal with this one
  $req->ack_extensions('BODY');
  
  $ctl->next;
}


sub _exec_mail_command {
  my ($ctl, $args) = @_;
  my ($sess, $req) = @$args;

  # Store the reverse path on our transaction
  my $rev_path = $sess->path_class->new({
    addr       => $req->args->[0],
    extensions => $req->extensions,
  });
  $sess->transaction->reverse_path($rev_path);
  
  $sess->ok_250;
  return $ctl->done;
}


1;