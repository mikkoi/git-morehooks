package Git::MoreHooks::GitRepoAdmin;

## no critic (InputOutput::RequireCheckedSyscalls)
## no critic (ValuesAndExpressions::ProhibitMagicNumbers)
## no critic (Documentation::RequirePodAtEnd)
## no critic (Documentation::RequirePodSections)
## no critic (ValuesAndExpressions::RequireInterpolationOfMetachars)
## no critic (ControlStructures::ProhibitPostfixControls)

use strict;
use warnings;
use utf8;
use feature qw( say );

# ABSTRACT: Integrate with .git-repo-admin

# VERSION: generated by DZP::OurPkgVersion

=head1 STATUS

Package Git::MoreHooks is currently being developed so changes in the existing hooks are possible.


=head1 SYNOPSIS

Git::MoreHooks::GitRepoAdmin is a plugin for
L<Git::Hooks|Git::Hooks>.

=for Pod::Coverage check_commit_at_client check_commit_at_server

=for Pod::Coverage check_ref


=head1 DESCRIPTION

This plugin works with L<.git-admin-repo|https://github.com/mikkoi/.git-repo-admin>.

It has several functions:

=over

=item * B<Server Side>

On server side during C<git push> it updates the Git hooks automatically
when there is configuration changes,
i.e. when the VERSION file is updated with a greater number than earlier.

=item * B<Client Side>


On client side during C<git pull> it only informs
the user when there is configuration changes.
It does not perform any changes to user's repo.

=back


=head1 USAGE

To enable GitRepoAdmin plugin, you need
to add it to the githooks.plugin configuration option:

    git config --add githooks.plugin Git::MoreHooks::GitRepoAdmin

GitRepoAdmin plugin attaches itself to the following Git hooks:

=over

=item * B<post-merge>

This hook is invoked by L<git-merge|https://git-scm.com/docs/git-merge>,
which happens when a C<git pull> is done on a local repository.

=item * B<post-receive>

This hook is invoked by L<git-receive-pack|https://git-scm.com/docs/git-receive-pack>
when it reacts to C<git push>
and updates reference(s) in its repository. It executes on the remote
repository once after all the refs have been updated.

=back


=head1 CONFIGURATION

This plugin is configured by the following git options.

=head2 githooks.gitrepoadmin.ref REFSPEC

By default this plugin only reacts to updates on branches B<main>
or B<master>. If you want to
react to some other refs (usually some branch under
refs/heads/), you may specify them with one or more instances of this
option. N.B. Other good candidates are, for instance, branches
B<develop> and B<release>.

The refs can be specified as a complete ref name
(e.g. "refs/heads/master") or by a regular expression starting with a
caret (C<^>), which is kept as part of the regexp
(e.g. "^refs/heads/(master|fix)").

Default value for REFSPEC is [ '^refs/heads/main$', '^refs/heads/master$' ].

N.B. REFSPEC must not match two or more branch names in the repo.

N.B.2. Due to the latest change of default branch name from B<master> to B<main>,
both names are now supported by default. However, as above, the repository
must not have both of them. If you want to have both of them,
then you must define REFSPEC to match only one.


=head1 EXPORTS

This module exports the following routines that can be used directly
without using all of Git::Hooks infrastructure.

=head2 check_affected_refs_client_side GIT, INT

This is the routine used to implement the C<post-merge>
hook. It needs a C<Git::More> object and an integer
telling if this was a squash merge (1) or not (0).

=head2 check_affected_refs_server_side GIT

This is the routing used to implement
the C<post-receive> hook. It needs a C<Git::More> object.

=head1 NOTES

Thanks go to Gustavo Leite de Mendonça Chaves for his
L<Git::Hooks|https://metacpan.org/pod/Git::Hooks> package.

=head1 BUGS AND LIMITATIONS

No known bugs.

=cut


use Git::Hooks 3.000000;
use English qw( -no_match_vars );
use Path::Tiny;
use Cwd;
use File::Spec;
use File::Temp qw/ tempfile tempdir /;
use Log::Any qw{$log};

my $PKG = __PACKAGE__;
my ($CFG) = __PACKAGE__ =~ /::([^:]+)$/msx;
$CFG = 'githooks.' . $CFG;

#############
# Grok hook configuration, check it and set defaults.

sub _setup_config {
    my ($git) = @_;
    $log->debugf( __PACKAGE__ . '::_setup_config(%s):', '$git' );

    my $config = $git->get_config();
    $log->tracef( __PACKAGE__ . '::_setup_config(): Current Git config:\n%s.', $config );

    $config->{ lc $CFG } //= {};

    my $default = $config->{ lc $CFG };
    $default->{'ref'} //= [ '^refs/heads/main$', '^refs/heads/master$' ];

    return;
}

sub _current_version {
    my ( $git, $dir ) = @_;
    $log->debug( ( caller 0 )[3], '( ', $git, ', ', $dir, ')' );
    my $ver_file_cnt = path( File::Spec->catdir( $dir, 'VERSION' ) )->slurp_utf8;
    $log->debug( ( caller 0 )[3], ': ver_file_cnt=', $ver_file_cnt );
    my ($hooks_cfg_ver) = $ver_file_cnt =~ m/^([[:digit:]]+)$/msx;
    return if !$hooks_cfg_ver;
    return $hooks_cfg_ver;
}

sub _new_version {
    my ( $git, $ref, $dir ) = @_;
    $log->debug( ( caller 0 )[3], '( ', $git, ', ', $ref, ', ', $dir, ')' );

    my $filepath     = File::Spec->catdir( $dir, 'VERSION' );
    my $object       = "$ref:$filepath";
    my $ver_file_cnt = $git->run(
        'cat-file',
        '-p', $object,
        {
            env => {

                # Eliminate the effects of system wide and global configuration.
                GIT_CONFIG_NOSYSTEM => 1,
                XDG_CONFIG_HOME     => undef,
                HOME                => undef,
            },
        },
    );

    $log->debug( ( caller 0 )[3], ': ver_file_cnt=', $ver_file_cnt );
    my ($hooks_cfg_ver) = $ver_file_cnt =~ m/^([[:digit:]]+)$/msx;
    return if !$hooks_cfg_ver;
    return $hooks_cfg_ver;
}

sub _ref_matches {
    my ( $git, $our_refs, $branches ) = @_;
    $log->debug( ( caller 0 )[3], '( ', ( join q{:}, @{$our_refs} ), ', ', ( join q{:}, @{$branches} ), ')' );

    my @matches;
    foreach my $our_ref ( @{$our_refs} ) {
        my @m = grep { m/$our_ref/msx } @{$branches};
        push @matches, @m;
    }

    return @matches;
}

sub _update_server_side {
    my ( $git, $ref, $dir ) = @_;
    $log->debug( ( caller 0 )[3], '( ', $git, ', ', $ref, ', ', $dir, ')' );

    my $tmp = File::Temp->new();

    # Hook is always run with cdw as repo root dir.
    my $filepath     = File::Spec->catdir( $dir, 'initialize-server.sh' );
    my $object       = "$ref:$filepath";
    my $exe_file_cnt = $git->run(
        'cat-file',
        '-p', $object,
        {
            env => {

                # Eliminate the effects of system wide and global configuration.
                GIT_CONFIG_NOSYSTEM => 1,
                XDG_CONFIG_HOME     => undef,
                HOME                => undef,
            },
        },
    );
    $log->debug( ( caller 0 )[3], ': exe_file_cnt=', $exe_file_cnt );
    print {$tmp} $exe_file_cnt;
    my $tmp_filename = $tmp->filename;
    $log->debug( ( caller 0 )[3], ': tmp_filename=', $tmp_filename );
    local $OUTPUT_AUTOFLUSH = 1;
    system 'bash', $tmp_filename, $ref;

    return;
}

##########

sub check_affected_refs_client_side {
    my ( $git, $is_squash_merge ) = @_;
    $log->debug( ( caller 0 )[3], '( ', $git, '( ', ( $is_squash_merge // 'undef' ), ')' );
    $is_squash_merge = 0 if ( !defined $is_squash_merge );

    _setup_config($git);
    $log->debug( ( caller 0 )[3], ': cwd=', cwd );

    # Hook is always run with cdw as repo root dir.
    my $curr_ver = _current_version( $git, '.git/.git-repo-admin' );
    $log->debug( ( caller 0 )[3], ': curr_ver=', $curr_ver );

    # We cannot use $git->get_affected_refs() because post-merge hook
    # does not get information about which branches are affected.
    # Don't know why!!!
    # So instead we just work with the only branch in the config.
    my @our_refs = $git->get_config( $CFG => 'ref' );
    $log->debug( ( caller 0 )[3], ': our_refs=', ( join q{:}, @our_refs ) );
    my $branches_raw = $git->run(
        'for-each-ref',
        '--format',
        '%(refname)',
        {
            env => {

                # Eliminate the effects of system wide and global configuration.
                GIT_CONFIG_NOSYSTEM => 1,
                XDG_CONFIG_HOME     => undef,
                HOME                => undef,
            },
        },
    );
    my @branches = split qr{\n}msx, $branches_raw;
    $log->debug( ( caller 0 )[3], ': branches=', ( join q{:}, @branches ) );

    my @matches = _ref_matches( $git, \@our_refs, \@branches );
    if ( @matches > 1 ) {
        $git->fault('Config variable \'ref\' matches with more than one branch.');
        return scalar @matches;
    }
    elsif ( @matches == 0 ) {
        $git->fault('Config variable \'ref\' does not match with any branch.');
        return 1;
    }

    # Okay, no errors in the config.
    # We always proceed to read the VERSION from the hook config branch.
    my $new_ver = _new_version( $git, $matches[0], '.git-repo-admin' );
    $log->debug( ( caller 0 )[3], ': new_ver=', $new_ver );
    if ( $new_ver > $curr_ver ) {
        $log->debug( ( caller 0 )[3], 'Newer version detected. Update config.' );
        say '********************************************************************************';
        say '*                          UPDATE CLIEND SIDE HOOKS                            *';
        say '*               Run .git-repo-admin/install-client-hooks.sh                    *';
        say '*                    ATTN. Switch to right branch first!                       *';
        say '********************************************************************************';
    }

    return 0;
}

sub check_affected_refs_server_side {
    my ($git) = @_;
    $log->debug( ( caller 0 )[3], '( ', $git, ')' );

    _setup_config($git);
    my $curr_ver = _current_version( $git, '.git-repo-admin' );
    $log->debug( ( caller 0 )[3], ': curr_ver=', $curr_ver );

    # We're only interested in branches
    my @refs = grep { m{^refs/heads/}msx } $git->get_affected_refs();
    return 1 unless @refs;

    my @our_refs = $git->get_config( $CFG => 'ref' );
    $log->debug( ( caller 0 )[3], ': our_refs=', ( join q{:}, @our_refs ) );

    # my ($r, $match) = _ref_matches( $git, \@our_refs, \@refs );
    my @matches = _ref_matches( $git, \@our_refs, \@refs );
    $log->debug( ( caller 0 )[3], ': matches=', ( join q{:}, @matches ) );
    if ( @matches > 1 ) {
        $git->fault('Config variable \'ref\' matches with more than one branch.');
        $log->debug( ( caller 0 )[3], '(): ' . scalar @matches );
        return scalar @matches;
    }
    elsif ( @matches == 1 ) {
        my $new_ver = _new_version( $git, $matches[0], '.git-repo-admin' );
        $log->debug( ( caller 0 )[3], ': new_ver=', $new_ver );
        if ( $new_ver > $curr_ver ) {
            $log->debug( ( caller 0 )[3], 'Newer version detected. Update config.' );
            _update_server_side( $git, $matches[0], '.git-repo-admin' );
        }
        $log->debug( ( caller 0 )[3], '(): 0' );
        return 0;
    }

    # On server side we get the affected refs via the hook, and the main/master
    # doesn't need to be one of them, if it wasn't updated.

}

# Install hooks
POST_MERGE \&check_affected_refs_client_side;
POST_RECEIVE \&check_affected_refs_server_side;

1;
