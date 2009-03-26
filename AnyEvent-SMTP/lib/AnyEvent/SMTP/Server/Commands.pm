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
  
  $self->hook('parse_rcpt_command',    \&_parse_rcpt_command   );
  $self->hook('validate_rcpt_command', \&_validate_rcpt_command);
  $self->hook('execute_rcpt_command',  \&_exec_rcpt_command    );

  $self->hook('parse_noop_command',   \&_parse_noop_command);
  $self->hook('execute_noop_command', \&_exec_noop_command );
  
  $self->hook('execute_rset_command', \&_exec_rset_command );
  
  $self->hook('execute_quit_command', \&_exec_quit_command);
  
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
    # we ignore @other arguments as suggested in
    # rfc 5321, sec 4.1.1.1 para 2:
    # 
    #   RFC 2821, and some earlier informal practices, encouraged
    #   following the literal by information that would help to identify
    #   the client system. That convention was not widely supported, and
    #   many SMTP servers considered it an error. In the interest of
    #   interoperability, it is probably wise for servers to be prepared
    #   for this string to occur, but SMTP clients SHOULD NOT send it.
    #
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
  
  return _parse_address_and_extensions($ctl, $args, $sess, $req, $rest);
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


### RCPT TO:<address> (EXT(=VALUE)?)*
sub _parse_rcpt_command {
  my ($ctl, $args) = @_;
  my ($sess, $req, $rest) = @$args;

  # Make sure we have our mandatory first argument  
  unless ($rest =~ s/^to:\s*//i) {
    $sess->err_501_syntax_error("Missing 'TO:' argument");
    return $ctl->done;
  }
  
  return _parse_address_and_extensions($ctl, $args, $sess, $req, $rest);
}

sub _validate_rcpt_command {
  my ($ctl, $args) = @_;
  my ($sess, $req) = @$args;
  
  # No MAIL FROM:, bad sequence: cf rfc5321, seq 3.3, para 10
  # 
  #   If a RCPT command appears without a previous MAIL command, the
  #   server MUST return a 503 "Bad sequence of commands" response
  # 
  if (! $sess->has_transaction) {
    $sess->err_503_bad_sequence_cmds;
    return $ctl->done;
  }
  
  $ctl->next;
}

sub _exec_rcpt_command {
  my ($ctl, $args) = @_;

  $args->[0]->call('check_rcpt_address', $args, sub {
    my (undef, $args, $is_ok) = @_;
    my ($sess, $req) = @$args;

    if ($is_ok) {
      # Store the forward path on our transaction
      my $fwd_path = $sess->path_class->new({
        addr       => $req->args->[0],
        extensions => $req->extensions,
      });
      my $rcpts = $sess->transaction->forward_paths;
      push @$rcpts, $fwd_path;
      
      $sess->ok_250;
    }
    else {
      $sess->err_553_action_not_taken_mbox_not_allowed;
    }   
    
    return $ctl->done;
  });
}


### Shared parser (MAIL and RCPT) for address and extensions

sub _parse_address_and_extensions {
  my ($ctl, $args, $sess, $req, $rest) = @_;
  
  # Mark $rest as parsed, we'll take care of the rest now
  my ($addr, @exts) = split_smtp_cmd_args($rest);
  $args->[2] = '';
  
  # parse and validate reverse-path, store it in request args
  $addr = parse_smtp_cmd_mail_addr($addr);
  if (!defined $addr) {
    $sess->err_501_syntax_error('Missing address');
    return $ctl->done;
  }
  push @{$req->args}, $addr;
  
  # Parse extenions and store them in our request
  # rfc5321, sec 4.1.1.11 requires a 555 error in this case
  my $exts = parse_smtp_cmd_extensions(@exts);
  if (!$exts) {
    $sess->err_555_bad_mail_rcpt_args("Unable to parse '".join(' ', @exts)."'");
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


### NOOP command
sub _parse_noop_command {
  my ($ctl, $args) = @_;
 
  # Ignore arguments
  # See rfc5321, sect 4.1.1.9
  $args->[2] = '';

  $ctl->next;  
}

sub _exec_noop_command {
  my ($ctl, $args) = @_;
  my ($sess) = @$args;

  $sess->ok_250;
  
  return $ctl->done;
}


### RSET command
sub _exec_rset_command {
  my ($ctl, $args) = @_;
  my ($sess) = @$args;

  $sess->clear_transaction;
  $sess->ok_250;
  
  return $ctl->done;
}


### QUIT command
sub _exec_quit_command {
  my ($ctl, $args) = @_;
  my ($sess) = @$args;

  $sess->clear_transaction;
  $sess->ok_221_bye_now;
  $sess->disconnect;
  
  return $ctl->done;
}

1;