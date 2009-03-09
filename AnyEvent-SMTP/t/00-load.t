#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'AnyEvent::SMTP' );
}

diag( "Testing AnyEvent::SMTP $AnyEvent::SMTP::VERSION, Perl $], $^X" );
