package AnyEvent::SMTP::Utils;

use strict;
use warnings;
use base qw( Exporter );

@AnyEvent::SMTP::Utils::EXPORT    = qw();
@AnyEvent::SMTP::Utils::EXPORT_OK = qw( 
  split_smtp_cmd
  split_smtp_cmd_args
  parse_smtp_cmd_mail_addr
  parse_smtp_cmd_extensions
);
%AnyEvent::SMTP::Utils::EXPORT_TAGS = (
    all => [ @AnyEvent::SMTP::Utils::EXPORT_OK ],
);


### SMTP command splitter
sub split_smtp_cmd {
  my ($line) = @_;

  # Accept \s+ with empty params, rfc5321, 4.1.1, par 1 (SHOULD)
  my ($cmd, $rest) = $line =~ /^(\w{1,12})(?:\s+(.*))?$/;
  return unless $cmd;

  my $canon_cmd = lc($cmd);
  
  return ($canon_cmd, $rest||'', $cmd),
}


### SMTP Command arguments spliter
sub split_smtp_cmd_args {
  my ($rest) = @_;
  $rest =~ s/^\s+|\s+$//g;

  return split(/\s+/, $rest);
}


### SMTP mail address parser
sub parse_smtp_cmd_mail_addr {
  my ($addr) = @_;
  return unless $addr;
  
  # TODO: validate and canonify address
  $addr =~ s/^<(.*)>$/$1/;

  return $addr;
}

sub parse_smtp_cmd_extensions {
  my %exts;
  foreach my $ext (@_) {
    my ($key, $value) = $ext =~ /^([^=]+)(?:=(.+))?$/;
    return unless $key;
    $exts{$key} = $value;
  }
  
  return \%exts;
}


1;