## no critic (Documentation::PodSpelling)
## no critic (Documentation::RequirePodAtEnd)
## no critic (Documentation::RequirePodSections)
## no critic (ValuesAndExpressions::RequireInterpolationOfMetachars)

package Git::MoreHooks::CheckCommitAuthorFromMailmap;

use strict;
use warnings;
use 5.010000;
use utf8;

# ABSTRACT: Check Git commit author by using the mailmap file.

# VERSION: generated by DZP::OurPkgVersion

=head1 STATUS

Package Git::MoreHooks is currently being developed so changes in the existing hooks are possible.


=head1 SYNOPSIS

Use package via
L<Git::Hooks|Git::Hooks>
interface (configuration in Git config file).

=for Pod::Coverage check_commit_at_client check_commit_at_server

=for Pod::Coverage check_ref


=head1 DESCRIPTION

By its very nature, the Git VCS (version control system) is open
and with very little access control. It is common in many instances to run
Git under one user id (often "git") and allowing access to it
via L<SSH|http://en.wikipedia.org/wiki/Secure_Shell> and
L<public keys|http://en.wikipedia.org/wiki/Public-key_cryptography>.
This means that user can push commits without any control on either commit
message or the commit author.

This plugin allows one to enforce policies on the author information
in a commit. Author information consists of author name and author email.
Email is the more important of these. In principle, email is used to identify
committers, and in some Git clients,
L<GitWeb|http://git-scm.com/book/en/v2/Git-on-the-Server-GitWeb>
WWW-interface, for instance,
email is also used to show the L<Gravatar|http://en.gravatar.com> of the committer.
The common way for user to set the author is to use the
(normally global)
configuration options I<user.name> and I<user.email>. When doing a commit,
user can override these via the command line option I<--author>.

=head1 USAGE

To enable CheckCommitAuthorFromMailmap plugin, you need
to add it to the githooks.plugin configuration option:

    git config --add githooks.plugin Git::MoreHooks::CheckCommitAuthorFromMailmap

Git::MoreHooks::CheckCommitAuthorFromMailmap plugin hooks itself to the hooks below:

=over

=item * B<pre-commit>

This hook is invoked during the commit, to check if the commit author
name and email address comply.

=item * B<update>

This hook is invoked multiple times in the remote repository during
C<git push>, once per branch being updated, to check if the commit author
name and email address of all commits being pushed comply.

=item * B<pre-receive>

This hook is invoked once in the remote repository during C<git push>,
to check if the commit author name and email address of all commits
being pushed comply.

=item * B<ref-update>

This hook is invoked when a push request is received by Gerrit Code
Review, to check if the commit author name and email address of all commits being
pushed comply.

=item * B<patchset-created>

This hook is invoked when a push request is received by Gerrit Code
Review for a virtual branch (refs/for/*), to check if the commit
author name and email address of all commits being pushed comply.

=item * B<draft-published>

The draft-published hook is executed when the user publishes a draft change,
making it visible to other users.

=back

=head1 CONFIGURATION

This plugin is configured by the following git options.

=head2 githooks.checkcommitauthorfrommailmap.ref REFSPEC

By default, the message of every commit is checked. If you want to
have them checked only for some refs (usually some branch under
refs/heads/), you may specify them with one or more instances of this
option.

The refs can be specified as a complete ref name
(e.g. "refs/heads/master") or by a regular expression starting with a
caret (C<^>), which is kept as part of the regexp
(e.g. "^refs/heads/(master|fix)").

=head3 githooks.checkcommitauthorfrommailmap.match-mailmap-name [01]

Match also with the mailmap name, not just with the email address.
Default: 1 (on).

=head3 githooks.checkcommitauthorfrommailmap.allow-mailmap-aliases [01]

Allow matching also with mailmap alias (commit) email (and name if allowed),
not just proper email (and name if allowed, see
B<match-mailmap-name>).
Default: 1 (On).

=head2 Mailmap File

In mailmap file the author can be matched against both
the proper name and email or the alias (commit) name and email.
For mailmap contents, please see
L<git-shortlog - MAPPING AUTHORS|http://git-scm.com/docs/git-shortlog#_mapping_authors>.

The mailmap file is located according to Git's normal preferences:

=over

=item 1 Default mailmap.

If exists, use file F<HEAD:.mailmap>, located at the root
of the repository.

=item 2 Configuration variable I<mailmap.file>.

The location of an augmenting mailmap file.
The default mailmap is loaded first,
then the mailmap file pointed to by this variable. The contents of this
mailmap will take precedence over the default one's contents (when needed).
File should, perhaps, be in UTF-8 format.

The location of the
mailmap file may be in a repository subdirectory, or somewhere outside
of the repository itself. If the repo is a bare repository, then this
config option will raise an error. Use variable I<mailmap.blob> if file is in
the repository. If file cannot be found, this will raise an error.

=item 3 Configuration variable I<mailmap.blob>.

If the repo is a bare repository, and mailmap is in it, then this
config variable should be used.
It points to a Git blob in the bare repo. The contents of this
mailmap will take precedence over the default one's contents (when needed) and the
augmenting mailmap file's contents (var I<mailmap.file>).

=back


=head1 EXPORTS

This module exports the following routines that can be used directly
without using all of Git::Hooks infrastructure.

=head2 check_commit_at_client GIT

This is the routine used to implement the C<pre-commit> hook. It needs
a C<Git::More> object.

=head2 check_commit_at_server GIT, COMMIT

This is the routine used to implement the C<pre-commit> hook. It needs
a C<Git::More> object and a commit hash from C<Git::More::get_commit()>.

=head2 check_affected_refs GIT

This is the routing used to implement the C<update> and the
C<pre-receive> hooks. It needs a C<Git::More> object.

=head2 check_patchset GIT, HASH

This is the routine used to implement the C<patchset-created> Gerrit
hook. It needs a C<Git::More> object and the hash containing the
arguments passed to the hook by Gerrit.

=head1 NOTES

Thanks go to Gustavo Leite de Mendonça Chaves for his
L<Git::Hooks|https://metacpan.org/pod/Git::Hooks> package.

=head1 BUGS AND LIMITATIONS

The hook reads the file F<HEAD:.mailmap> with git command C<show>.
This is clearly the wrong approach for several reasons.
Firstly, C<git-show> is a 
L<porcelain|https://mirrors.edge.kernel.org/pub/software/scm/git/docs/git.html>
command, not a plumbing command.
Secondly, C<git-show> fails with an error if there is no commits in the repository.
Thirdly, C<git-show> only shows committed files.
In the B<pre-commit> hook we want to read a file in the working directory.


=cut

use Git::Hooks;
use Path::Tiny;
use Log::Any qw{$log};
require Git::Mailmap;

my $PKG = __PACKAGE__;
my ($CFG) = __PACKAGE__ =~ /::([^:]+)$/msx;
$CFG = 'githooks.' . $CFG;

#############
# Grok hook configuration, check it and set defaults.

sub _setup_config {
    my ($git) = @_;

    my $config = $git->get_config();
    $log->debugf( '_setup_config(): Current Git config:\n%s.', $config );

    $config->{ lc $CFG } //= {};

    my $default = $config->{ lc $CFG };
    $default->{'match-mailmap-name'}    //= ['1'];
    $default->{'allow-mailmap-aliases'} //= ['1'];

    return;
}

##########

sub check_commit_at_client {
    my ($git) = @_;

    my $current_branch = $git->get_current_branch();
    return 1 unless $git->is_reference_enabled( $current_branch );

    my $author_name  = $ENV{'GIT_AUTHOR_NAME'};
    my $author_email = '<' . $ENV{'GIT_AUTHOR_EMAIL'} . '>';

    return _check_author( $git, $author_name, $author_email );
}

sub check_commit_at_server {
    my ( $git, $commit ) = @_;

    my $author_name  = $commit->{'author_name'};
    my $author_email = '<' . $commit->{'author_email'} . '>';

    return _check_author( $git, $author_name, $author_email );
}

sub _check_author {
    my ( $git, $author_name, $author_email ) = @_;

    _setup_config($git);

    return 1 if $git->im_admin();

    my $errors = 0;
    _check_mailmap( $git, $author_name, $author_email ) or ++$errors;

    return $errors == 0;
}

sub _check_mailmap {
    my ( $git, $author_name, $author_email ) = @_;

    my $errors            = 0;
    my $author            = $author_name . q{ } . $author_email;
    my $mailmap           = Git::Mailmap->new();
    my $mailmap_as_string = $git->run( 'show', 'HEAD:.mailmap' );
    if ( defined $mailmap_as_string ) {
        $mailmap->from_string( 'mailmap' => $mailmap_as_string );
        $log->debugf( '_check_mailmap(): HEAD:.mailmap read in.' . ' Content from Git::Mailmap:\n%s', $mailmap->to_string() );
    }

    # 2) Config variable mailmap.file
    my $mapfile_location = $git->get_config( 'mailmap.' => 'file' );
    if ( defined $mapfile_location ) {
        if ( -e $mapfile_location ) {
            my $file_as_str = Path::Tiny->file($mapfile_location)->slurp_utf8;
            $mailmap->from_string( 'mailmap' => $file_as_str );
            $log->debugf( '_check_mailmap(): mailmap.file (%s) read in.' . ' Content from Git::Mailmap:\n%s',
                $mapfile_location, $mailmap->to_string() );
        }
        else {
            $git->error( $PKG, 'Config variable \'mailmap.file\'' . ' does not point to a file.' );
        }
    }

    # 3) Config variable mailmap.blob
    my $mapfile_blob = $git->get_config( 'mailmap.' => 'blob' );
    if ( defined $mapfile_blob ) {
        if ( my $blob_as_str = $git->command( 'show', $mapfile_blob ) ) {
            $mailmap->from_string( 'mailmap' => $blob_as_str );
            $log->debugf( '_check_mailmap(): mailmap.blob (%s) read in.' . ' Content from Git::Mailmap:\n%s',
                $mapfile_blob, $mailmap->to_string() );
        }
        else {
            $git->error( $PKG, 'Config variable \'mailmap.blob\'' . ' does not point to a file.' );
        }
    }

    my $verified = 0;

    # Always search (first) among proper emails (and names if wanted).
    my %search_params = ( 'proper-email' => $author_email );
    if ( $git->get_config( $CFG => 'match-mailmap-name' ) eq '1' ) {
        $search_params{'proper-name'} = $author_name;
    }
    $log->debugf( '_check_mailmap(): search_params=%s.', \%search_params );
    $verified = $mailmap->verify(%search_params);
    $log->debugf( '_check_mailmap(): verified=%s.', $verified );

    # If was not found among proper-*, and user wants, search aliases.
    if (  !$verified
        && $git->get_config( $CFG => 'allow-mailmap-aliases' ) eq '1' )
    {
        my %c_search_params = ( 'commit-email' => $author_email );
        if ( $git->get_config( $CFG => 'match-mailmap-name' ) eq '1' ) {
            $c_search_params{'commit-name'} = $author_name;
        }
        $log->debugf( '_check_mailmap(): c_search_params=%s.', \%c_search_params );
        $verified = $mailmap->verify(%c_search_params);
    }
    if ( $verified == 0 ) {
        $git->error( $PKG, 'commit author ' . "'\Q$author\Q' does not match in mailmap file." )
          and ++$errors;
    }

    return $errors == 0;
}

sub check_ref {
    my ( $git, $ref ) = @_;

    return 1 unless $git->is_reference_enabled( $ref );

    my $errors = 0;
    foreach my $commit ( $git->get_affected_ref_commits($ref) ) {
        check_commit_at_server( $git, $commit )
          or ++$errors;
    }

    return $errors == 0;
}

# This routine can act both as an update or a pre-receive hook.
sub check_affected_refs {
    my ($git) = @_;

    _setup_config($git);

    return 1 if $git->im_admin($git);

    my $errors = 0;

    foreach my $ref ( $git->get_affected_refs() ) {
        check_ref( $git, $ref )
          or ++$errors;
    }

    return $errors == 0;
}

sub check_patchset {
    my ( $git, $opts ) = @_;

    _setup_config($git);

    my $sha1   = $opts->{'--commit'};
    my $commit = $git->get_commit($sha1);

    my $branch = $opts->{'--branch'};
    $branch = "refs/heads/$branch"
      unless $branch =~ m:^refs/:;
    return 1 unless $git->is_reference_enabled( $branch );

    return check_commit_at_server( $git, $commit );
}

# Install hooks
PRE_COMMIT \&check_commit_at_client;
UPDATE \&check_affected_refs;
PRE_RECEIVE \&check_affected_refs;
REF_UPDATE \&check_affected_refs;
PATCHSET_CREATED \&check_patchset;
DRAFT_PUBLISHED \&check_patchset;

1;

