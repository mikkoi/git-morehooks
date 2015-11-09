#!perl -T
use 5.006;
use strict;
use warnings;
use Test::Most;

use Git::MoreHooks::TriggerJenkins;

my $ref = 'refs/origin/mikko.koivunalho/ABC-987';
is( Git::MoreHooks::TriggerJenkins::job_name($ref), 'mikko.koivunalho-ABC-987',
        'Job name extracted from ref ok.');

is( 1,1, 'Is okay');
done_testing();

