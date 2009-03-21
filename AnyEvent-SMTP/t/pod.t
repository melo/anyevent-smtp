#!perl -T

use strict;
use warnings;
use Test::More;

# Ensure a recent version of Test::Pod
my $min_tp = 1.22;
eval "use Test::Pod $min_tp";
plan skip_all => "Test::Pod $min_tp required for testing POD" if $@;
plan skip_all => "Enable Pod tests with ENV TEST_AUTHOR_POD=1"
    unless $ENV{TEST_AUTHOR_POD};

all_pod_files_ok();
