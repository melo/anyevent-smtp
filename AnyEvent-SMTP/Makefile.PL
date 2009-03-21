use inc::Module::Install;

name     'AnyEvent-SMTP';
all_from 'lib/AnyEvent/SMTP.pm';
author   'Pedro Melo <melo@cpan.org>';
license  'perl';

requires 'Mouse' => 0;
requires 'AnyEvent' => 0;
requires 'AnyEvent::Handle' => 0;
requires 'AnyEvent::Socket' => 0;
requires 'Async::Hooks' => '0.04';

build_requires 'Test::More';
build_requires 'Test::Exception';
build_requires 'Test::Deep';

auto_install;

WriteAll;
