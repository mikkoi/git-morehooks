#!perl
## no critic (ValuesAndExpressions::ProhibitMagicNumbers)
## no critic (ValuesAndExpressions::ProhibitEscapedCharacters) -- the bytes under test MUST be escapes: this file has to stay ASCII, which is
## the rule the plugin enforces, and the characters would be invisible or
## misleading in the source if written out -- which is the point of them
use strict;
use warnings;
use Test2::V0;

use Log::Any::Adapter ( 'Stderr', log_level => 'warning' );
use Git::Hooks::Test ':all';
use English    qw( -no_match_vars );
use Path::Tiny qw( path );

my ( $repo, $clone, $T );

# Eliminate the effects of system wide and global configuration.
my %git_test_env = (
    LC_ALL              => 'C',
    GIT_CONFIG_NOSYSTEM => 1,
    XDG_CONFIG_HOME     => undef,
    HOME                => undef,
);

my %author_env = (
    GIT_AUTHOR_NAME     => 'My Self',
    GIT_AUTHOR_EMAIL    => 'myself@example.com',
    GIT_COMMITTER_NAME  => 'My Self',
    GIT_COMMITTER_EMAIL => 'myself@example.com',
);

my %env = ( %git_test_env, %author_env );

sub setup_repos {
    ( $repo, undef, $clone, $T ) = new_repos();

    install_hooks( $repo,  undef, qw/pre-commit/ );
    install_hooks( $clone, undef, qw/update pre-receive/ );
    return;
}

sub set_config {
    my ( $git, @pairs ) = @_;

    if ( !eval { $git->run( qw( config --remove-section githooks.checknonascii ), { env => \%env } ); 1 } ) {
        note 'There was no githooks.checknonascii section to remove.';
    }
    while ( my ( $option, $setting ) = splice @pairs, 0, 2 ) {
        $git->run( 'config', '--add', "githooks.checknonascii.$option", $setting, { env => \%env } );
    }
    return;
}

# Bytes are written as escapes so this test file stays ASCII, which is the rule
# the plugin enforces. Writing them raw would make the fixture unreadable in
# exactly the way the plugin reports.
sub write_file {
    my ( $name, $bytes ) = @_;
    my $file = path( $T->child('repo'), $name );
    $file->parent->mkpath;
    $file->spew_raw($bytes);
    $repo->run( 'add', $name, { env => \%env } );
    return;
}

sub commit_ok {
    my ($testname) = @_;
    return test_ok( $testname, $repo, 'commit', '-m', 'A commit', { env => \%env } );
}

sub commit_nok {
    my ( $testname, $regex ) = @_;
    return test_nok_match( $testname, $regex, $repo, 'commit', '-m', 'A commit', { env => \%env } );
}

setup_repos();
$repo->run( qw/config githooks.plugin Git::MoreHooks::CheckNonASCII/, { env => \%env } );

# Plain ASCII is the case that must never be disturbed.
{
    set_config($repo);
    write_file( 'plain.txt', "nothing but ascii here\n" );
    commit_ok('a file of plain ascii is accepted');
}

# The attacks the plugin exists for, one per commit so each is reported alone.
{
    set_config($repo);

    write_file( 'bidi.txt', "a line with \xe2\x80\xae an override\n" );
    commit_nok( 'a bidirectional override is reported', qr/U[+]202E/msx );
    $repo->run( qw( reset --hard HEAD ), { env => \%env } );

    write_file( 'zwsp.txt', "ident\xe2\x80\x8bifier\n" );
    commit_nok( 'a zero width space is reported', qr/U[+]200B/msx );
    $repo->run( qw( reset --hard HEAD ), { env => \%env } );

    write_file( 'homoglyph.txt', "my \xd0\xb0ccount\n" );
    commit_nok( 'a cyrillic homoglyph is reported', qr/U[+]0430/msx );
    $repo->run( qw( reset --hard HEAD ), { env => \%env } );
}

# The case a check on decoded characters cannot see.
{
    set_config($repo);
    write_file( 'invalid.txt', "a bad \x80 byte\n" );
    commit_nok( 'a byte that is not valid UTF-8 is reported', qr/byte [ ] 0x80/msx );
    $repo->run( qw( reset --hard HEAD ), { env => \%env } );
}

# The report says where, and names the codepoint rather than printing it.
{
    set_config($repo);
    write_file( 'where.txt', "first line is fine\nsecond has \xe2\x80\x94 here\n" );
    commit_nok( 'the report gives file, line and byte', qr/where[.]txt:2 [ ] byte [ ] 12/msx );
    $repo->run( qw( reset --hard HEAD ), { env => \%env } );
}

# Binary files are skipped, or every PNG in the repository would fail.
{
    set_config($repo);
    write_file( 'blob.bin', "\x89PNG\r\n\x1a\n\0\0\0\xe2\x80\xae\xff\xfe" );
    commit_ok('a binary file is skipped');
}

# skip, which is how the exceptions are expressed.
{
    set_config( $repo, skip => 't/data/*' );
    write_file( 't/data/fixture.txt', "deliberate \xe2\x80\x94 dash\n" );
    commit_ok('a skipped path is not reported');
}

{
    set_config( $repo, skip => 'qr{[.]utf8\z}' );
    write_file( 'quote.utf8', "deliberate \xe2\x80\x94 dash\n" );
    commit_ok('a skipped qr pattern is not reported');
}

# name, which narrows what is looked at.
{
    set_config( $repo, name => '*.pm' );
    write_file( 'notes.txt', "an em dash \xe2\x80\x94 outside the name pattern\n" );
    commit_ok('a file outside name is not checked');
}

{
    set_config( $repo, name => '*.pm' );
    write_file( 'lib/Thing.pm', "my \xe2\x80\x94 dash\n" );
    commit_nok( 'a file inside name is checked, and * crosses directories', qr/U[+]2014/msx );
    $repo->run( qw( reset --hard HEAD ), { env => \%env } );
}

# max-report, so a mostly-non-ASCII file cannot bury the output.
{
    set_config( $repo, 'max-report' => 2 );
    write_file( 'many.txt', ( "\xe2\x80\x94\n" x 5 ) );
    commit_nok( 'reporting stops at max-report and says how many remain', qr/and [ ] 3 [ ] more/msx );
    $repo->run( qw( reset --hard HEAD ), { env => \%env } );
}

# sizelimit, so an enormous blob is never slurped. The cost is that a file above
# the limit is not checked at all, which is why the default is far above source.
{
    set_config( $repo, 'sizelimit' => 32 );
    write_file( 'big.txt', ( 'a' x 64 ) . "\xe2\x80\x94\n" );
    commit_ok('a file over sizelimit is skipped, not read');
}

{
    set_config( $repo, 'sizelimit' => 4096 );
    write_file( 'small.txt', "under the limit \xe2\x80\x94 here\n" );
    commit_nok( 'a file under sizelimit is still checked', qr/U[+]2014/msx );
    $repo->run( qw( reset --hard HEAD ), { env => \%env } );
}

# The warning about the gap sizelimit opens. It is tied to an actual skip, and
# silent when CheckFile's sizelimit would refuse the file anyway.
{
    set_config( $repo, 'sizelimit' => 32 );
    if ( eval { $repo->run( qw( config --get githooks.checkfile.sizelimit ), { env => \%env } ); 1 } ) {
        $repo->run( qw( config --unset-all githooks.checkfile.sizelimit ), { env => \%env } );
    }
    write_file( 'unchecked.txt', ( 'a' x 64 ) . "\n" );
    my ( $ok, undef, undef, $err ) =
      test_command( $repo, 'commit', '-m', 'A commit', { env => \%env } );
    ok( $ok, 'a skipped file still commits' );
    like( $err, qr/was [ ] NOT [ ] checked/msx,          'and says the file was not checked' );
    like( $err, qr/sizelimit [ ] is [ ] not [ ] set/msx, 'and says nothing refuses it either' );
}

{
    set_config( $repo, 'sizelimit' => 32 );
    $repo->run( qw( config githooks.checkfile.sizelimit 32 ), { env => \%env } );
    write_file( 'covered.txt', ( 'b' x 64 ) . "\n" );
    my ( $committed, undef, undef, $stderr ) =
      test_command( $repo, 'commit', '-m', 'A commit', { env => \%env } );
    ok( $committed, 'a skipped file commits here too' );
    unlike( $stderr, qr/was [ ] NOT [ ] checked/msx, 'but says nothing: sizelimit covers the gap' );
    $repo->run( qw( config --unset-all githooks.checkfile.sizelimit ), { env => \%env } );
}

{
    set_config( $repo, 'sizelimit' => 32, 'no-warning-when-over-sizelimit' => 'true' );
    write_file( 'quiet.txt', ( 'c' x 64 ) . "\n" );
    my ( $committed, undef, undef, $stderr ) =
      test_command( $repo, 'commit', '-m', 'A commit', { env => \%env } );
    ok( $committed, 'a skipped file commits with the warning switched off' );
    unlike( $stderr, qr/was [ ] NOT [ ] checked/msx, 'and no-warning-when-over-sizelimit silences the report' );
}

# The suffix form. Read as a plain string this would have meant one BYTE, and
# The suffix form. Read as a plain string this would have meant one BYTE, and
# every file would have been skipped while the plugin looked configured.
{
    set_config( $repo, 'sizelimit' => '1k' );
    write_file( 'suffixed.txt', "well under a kibibyte \xe2\x80\x94 here\n" );
    commit_nok( 'sizelimit = 1k is a kibibyte, not one byte', qr/U[+]2014/msx );
    $repo->run( qw( reset --hard HEAD ), { env => \%env } );
}

# Line endings. A line number has to mean the same thing whatever wrote the file.
{
    set_config($repo);
    write_file( 'crlf.txt', "first line\r\nsecond \xe2\x80\x94 here\r\n" );
    commit_nok( 'CRLF: the finding is on line 2', qr/crlf[.]txt:2 [ ] byte [ ] 8/msx );
    $repo->run( qw( reset --hard HEAD ), { env => \%env } );
}

{
    set_config($repo);
    write_file( 'cr.txt', "first line\rsecond \xe2\x80\x94 here\r" );
    commit_nok( 'CR only: the finding is on line 2, not line 1', qr/cr[.]txt:2 [ ] byte [ ] 8/msx );
    $repo->run( qw( reset --hard HEAD ), { env => \%env } );
}

# A non-ASCII file NAME is an attack surface of its own.
{
    set_config($repo);
    write_file( "caf\xc3\xa9.txt", "plain ascii content\n" );
    commit_nok( 'a non-ascii file name is reported', qr/file [ ] name [ ] holds/msx );
    $repo->run( qw( reset --hard HEAD ), { env => \%env } );
}

# The server side, which rebase and --no-verify cannot evade.
{
    set_config($clone);
    $clone->run( qw/config githooks.plugin Git::MoreHooks::CheckNonASCII/, { env => \%env } );

    write_file( 'pushed.txt', "an override \xe2\x80\xae here\n" );
    $repo->run( 'commit', '--no-verify', '-m', 'Sneak it past the client', { env => \%env } );

    test_nok_match( 'a push is rejected by the server side', qr/U[+]202E/msx, $repo, 'push', 'clone', 'master', { env => \%env } );
}

done_testing();
