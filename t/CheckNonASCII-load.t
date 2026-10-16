#!perl
use strict;
use warnings;
use Test2::V0;

use Test2::Require::Module 'Git::MoreHooks::CheckNonASCII';
use Git::MoreHooks::CheckNonASCII;

BEGIN {
    can_ok( 'Git::MoreHooks::CheckNonASCII', '_setup_config' );
    can_ok( 'Git::MoreHooks::CheckNonASCII', '_compile_pattern' );
    can_ok( 'Git::MoreHooks::CheckNonASCII', '_patterns' );
    can_ok( 'Git::MoreHooks::CheckNonASCII', '_is_binary' );
    can_ok( 'Git::MoreHooks::CheckNonASCII', '_describe' );
    can_ok( 'Git::MoreHooks::CheckNonASCII', 'file_errors' );
    can_ok( 'Git::MoreHooks::CheckNonASCII', 'check_new_or_modified_files' );
    can_ok( 'Git::MoreHooks::CheckNonASCII', 'check_commit' );
    can_ok( 'Git::MoreHooks::CheckNonASCII', 'check_ref' );
    can_ok( 'Git::MoreHooks::CheckNonASCII', 'check_patchset' );
}

done_testing();
