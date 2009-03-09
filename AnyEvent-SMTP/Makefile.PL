use inc::Module::Install;

name     'AnyEvent-SMTP';
all_from 'lib/AnyEvent/SMTP.pm';
author   'Pedro Melo <melo@cpan.org>';
license  'perl';

build_requires 'Test::More';

auto_install;

WriteAll;

