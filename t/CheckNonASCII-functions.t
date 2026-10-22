#!perl
## no critic (Subroutines::ProtectPrivateSubs)
## no critic (ValuesAndExpressions::ProhibitMagicNumbers)
## no critic (ValuesAndExpressions::ProhibitEscapedCharacters) -- the bytes under test MUST be escapes: this file has to stay ASCII, which is
## the rule the plugin enforces, and the characters would be invisible or
## misleading in the source if written out -- which is the point of them
use strict;
use warnings;
use Test2::V0;

use Test2::Require::Module 'Git::MoreHooks::CheckNonASCII';
use Git::MoreHooks::CheckNonASCII;
use Git::Hooks::Test ':all';
use Log::Any::Adapter ('Null');

# The bytes are written as escapes on purpose: this file stays ASCII, which is
# the rule the plugin exists to enforce. A fixture written in the characters
# themselves would be unreadable in exactly the way the plugin reports.
subtest '_describe names a codepoint without printing it' => sub {
    my @cases = (
        [ "\xe2\x80\x94",     'U+2014',  3, 'em dash' ],
        [ "\xe2\x80\x8b",     'U+200B',  3, 'zero width space' ],
        [ "\xe2\x80\x8d",     'U+200D',  3, 'zero width joiner' ],
        [ "\xe2\x80\xae",     'U+202E',  3, 'right-to-left override' ],
        [ "\xd0\xb0",         'U+0430',  2, 'cyrillic small a, a homoglyph of ASCII a' ],
        [ "\xc2\xa0",         'U+00A0',  2, 'no-break space' ],
        [ "\xc2\xad",         'U+00AD',  2, 'soft hyphen' ],
        [ "\xef\xbb\xbf",     'U+FEFF',  3, 'byte order mark' ],
        [ "\xf0\x9f\x92\xa9", 'U+1F4A9', 4, 'a four byte sequence' ],
    );

    foreach my $case (@cases) {
        my ( $bytes, $want, $want_width, $label ) = @{$case};
        my ( $got, $got_width ) = Git::MoreHooks::CheckNonASCII::_describe( $bytes, 0 );
        is( $got,       $want,       "$label is named $want" );
        is( $got_width, $want_width, "$label accounts for $want_width bytes" );
    }

    done_testing;
};

subtest '_describe reports a byte that cannot be decoded' => sub {

    # This is the case a check reading decoded characters cannot see at all,
    # and the reason this plugin reads bytes.
    foreach my $byte ( "\x80", "\xbf", "\xc0", "\xc1", "\xf5", "\xfe", "\xff" ) {
        my ( $got, $width ) = Git::MoreHooks::CheckNonASCII::_describe( $byte, 0 );
        like( $got, qr/not [ ] valid [ ] UTF-8/msx, sprintf 'byte 0x%02X is reported as a byte', ord $byte );
        is( $width, 1, 'and accounts for one byte' );
    }

    # A truncated sequence: a valid lead byte with its continuation missing.
    my ( $got, $width ) = Git::MoreHooks::CheckNonASCII::_describe( "\xe2\x80", 0 );
    like( $got, qr/not [ ] valid [ ] UTF-8/msx, 'a truncated sequence is reported as a byte' );
    is( $width, 1, 'and does not consume past the end' );

    done_testing;
};

subtest '_is_binary agrees with git: a NUL byte' => sub {
    ok( Git::MoreHooks::CheckNonASCII::_is_binary("before\0after"), 'content with a NUL is binary' );
    ok( Git::MoreHooks::CheckNonASCII::_is_binary("\0"),            'a lone NUL is binary' );
    ok( !Git::MoreHooks::CheckNonASCII::_is_binary('plain ascii'),  'ascii is not binary' );
    ok(
        !Git::MoreHooks::CheckNonASCII::_is_binary("high \xe2\x80\x94 bytes"),
        'non-ASCII alone is not binary -- it is the thing we report'
    );
    ok( !Git::MoreHooks::CheckNonASCII::_is_binary(q{}), 'empty content is not binary' );

    done_testing;
};

subtest '_compile_pattern takes a glob or a qr' => sub {
    my $glob = Git::MoreHooks::CheckNonASCII::_compile_pattern('*.pm');
    like( 'lib/Foo.pm', $glob, 'a glob matches' );

    my $re = Git::MoreHooks::CheckNonASCII::_compile_pattern('qr{\Alib/.*[.]pm\z}');
    like( 'lib/Foo.pm', $re, 'a qr with braces matches' );
    unlike( 'xlib/Foo.pm', $re, 'and is anchored as written' );

    my $slash = Git::MoreHooks::CheckNonASCII::_compile_pattern('qr/[.]txt\z/');
    like( 'a.txt', $slash, 'a qr with slashes matches' );

    done_testing;
};

# The once-only warning is held per repository, not per process. A package
# variable would stay set after the first repository and the second would never
# be told -- which no hook test can catch, because each commit there runs in its
# own git process. This one exercises two repositories in ONE interpreter, which
# is what a long-running test suite or a persistent worker does.
subtest 'the once-only warning does not leak between repositories' => sub {
    my ( $first, undef, undef, undef ) = new_repos();
    my ( $other, undef, undef, undef ) = new_repos();

    # warnings returns an ARRAYREF, not a list. `my @w = warnings {...}` is a
    # one-element list holding that reference, so its count is always 1 and an
    # assertion on it passes whatever happened.
    my $one = warnings {
        Git::MoreHooks::CheckNonASCII::_announce_size_gap( $first, 'big.bin', 9_000_000, 100 );
    };
    is( scalar @{$one}, 1, 'the first repository is told' );

    my $again = warnings {
        Git::MoreHooks::CheckNonASCII::_announce_size_gap( $first, 'other.bin', 9_000_000, 100 );
    };
    is( scalar @{$again}, 0, 'and told only once' );

    my $elsewhere = warnings {
        Git::MoreHooks::CheckNonASCII::_announce_size_gap( $other, 'big.bin', 9_000_000, 100 );
    };
    is( scalar @{$elsewhere}, 1, 'the second repository is told as well' );

    done_testing;
};

done_testing();
