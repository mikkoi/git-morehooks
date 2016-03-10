## no critic (Documentation::PodSpelling)
## no critic (Documentation::RequirePodAtEnd)
## no critic (Documentation::RequirePodSections)
# no critic (ValuesAndExpressions::RequireInterpolationOfMetachars)
## no critic (InputOutput::RequireCheckedSyscalls)
#

package Git::MoreHooks::TriggerJenkins;

use strict;
use warnings;
use 5.010000;
use utf8;
use Data::Dumper;

# ABSTRACT: Git::Hooks plugin to create and remove jobs from Jenkins

# VERSION: generated by DZP::OurPkgVersion

=for stopwords Cxense

=cut

=head1 STATUS

Package Git::MoreHooks is currently being developed so changes in the existing hooks are possible.


=head1 SYNOPSIS

Use package via
L<Git::Hooks|Git::Hooks>
interface (configuration in Git config file).

=for Pod::Coverage handle_affected_refs


=head1 DESCRIPTION

This Git::Hooks plugin hooks itself to the hooks below to trigger
a build in Jenkins for the current branch.

=over

=item * B<post-receive>

This hook is invoked once for every branch
in the remote repository after a successful C<git push>.
It's used to trigger a build or builds in Jenkins.

=back

This plugin will create a Jenkins job with the name of the pushed branch.
This job will then be triggered.
The job is configured so that an email is sent to the user (the pushing user)
at the end of the run.
If the job already exists at Jenkins, its parameters are not updated. It is
only triggered again.

=head1 USAGE

To enable this hook add it to the githooks.plugin configuration
option:

    git config --add githooks.plugin Git::MoreHooks::TriggerJenkins

=head1 REQUIREMENTS

Required additional dependencies:

=over 8

=item Jenkins::API

=item Template

=back

These must be installed separately. They are not included as normal
dependencies for Git::MoreHooks package because they are needed only
by TriggerJenkins.

=head1 CONFIGURATION

The plugin is configured by the following git options.

=head2 githooks.triggerjenkins.ref REFSPEC

By default, all refs (branch names) are triggered.
To trigger only some refs (usually some branch under
refs/heads/), specify them with one or more instances of this
option.

The refs can be specified as a complete ref name
(e.g. "refs/heads/master") or by a regular expression starting with a
caret (C<^>), which is kept as part of the regexp
(e.g. "^refs/heads/(master|common\/TICKET-[0-9]+)").

TODO: Apply environment var USER to refs regular expression.

=head2 githooks.triggerjenkins.base-url URL

Specifies the Jenkins server HTTP URL. Only the base, e.g.
L<http://jenkins.company>. Required.

=head2 githooks.triggerjenkins.api-key USERNAME

Specifies the Jenkins server username. Required.

=head2 githooks.triggerjenkins.api-token TOKEN

Specifies the Jenkins server access token. Required.

=head2 githooks.triggerjenkins.project KEY

If set use this Jenkins project instead of extracting the name from ref name
and suffix in option job-template.

=head2 githooks.triggerjenkins.create-job [01]

# TODO Implement!
If set to 0, only trigger build if the job already exists.
If set to 1, create a new Jenkins job (project), unless it already exists).
Default 1.

=head2 githooks.triggerjenkins.job-template JOBSUFFIX FILENAME

If set, contains the suffix of the Jenkins jobname and the template filename.
Read the file as a L<Template Toolkit|Template> template file,
and use it to create a new Jenkins job. The suffix and the filename
are separated by space.

=head2 githooks.triggerjenkins.job-template-var KEY=VALUE

Define a key for value substitution in Jenkins job template. E.g.

    [githooks "triggerjenkins"]
        job-template-var = BUILD_DIR=/root/some/dir
        job-template-var = AUTH2_TOKEN=1234567890abcdefg

=head2 githooks.triggerjenkins.quiet [01]

If set to 1, do not print out anything to explain to user what was done.
If set to 0, explain to user what was done and print out the link
to the Jenkins job.
Default 0.

=head2 githooks.triggerjenkins.force [01]

# TODO Implement!
If set to 1, force a new build by cancelling the running build and scheduling
a new.
Default 0.

=head2 githooks.triggerjenkins.message-domain STRING

The domain name part of email or instant messager address,
i.e. S<"domain.com"> in S<<user.name@domain.com>>.
If not present, notification message address will not be configured into
Jenkins job.

=head2 githooks.triggerjenkins.override-message-address REFSPEC STRING

If present this option will override the notification message address.
A common setting would be to have branches like S<user.name/branch-name>
and these would be configured to send message to S<user.name@message-domain>.
Then this option would be configured to <Smaster all-dev@what.ever>.
This option can be set multiple times.
The branch name will be matched against all rows so several branch name
combinations/regular expressions are possible.

=head2 githooks.triggerjenkins.allow-commit-msg REGEXP

If no commit message in the push matches this regular expression,
then no build is triggered.
This can be useful if the repository has often small configuration changes
which need not or cannot be tested.

=head1 EXPORTS

This module exports routines that can be used directly without
using all of Git::Hooks infrastructure.

=head2 handle_commit_at_client GIT

This is the routine used to implement the C<post-commit> hook. It needs
a C<Git::More> object.
TODO Finish!

=head2 handle_affected_refs GIT

This is the routine used to implement the C<post-receive> hook. It needs a
C<Git::More> object for parameter.

=head1 SEE ALSO

=over

=item * L<Jenkins::API|https://metacpan.org/release/Jenkins-API>

=item * L<Git::Hooks|Git::Hooks>

=back

=head1 REFERENCES

=over

=item This script is heavily inspired (and sometimes derived) from
Gustavo Chaves'
L< Git::Hooks::CheckJira|https://metacpan.org/pod/Git::Hooks::CheckJira>.

=back

=head1 NOTES

Thanks go to Gustavo Leite de Mendonça Chaves for his
L<Git::Hooks|https://metacpan.org/pod/Git::Hooks> package.

This hook first implemented for Cxense Sweden AB. Published to CPAN with
Cxense Sweden AB's permission.

=cut

use Git::Hooks qw{:DEFAULT :utils};
use Path::Tiny;
use Log::Any qw{$log};
use Carp;
use Const::Fast;

my $PKG = __PACKAGE__;
( my $CFG = __PACKAGE__ ) =~ s/.*::/githooks./msx;

const my $LAST_CHAR_IN_STRING => -1;
const my $EMPTY_STRING        => q{};
const my $SPACE               => q{ };

=for Pod::Coverage setup_config configure_a_new_job trigger_branch

=for Pod::Coverage delete_job get_job_from_jenkins job_names_and_template_filenames

=for Pod::Coverage match_regexp_config_item

=cut

# Hook configuration.
sub setup_config {
    my ($git) = @_;

    my $config = $git->get_config();
    $log->debugf( 'setup_config(): Current Git config:\n%s.', $config );
    $config->{ lc $CFG } //= {};
    my $default = $config->{ lc $CFG };

    # Default values given as an array.
    # Array is default interpretation of config.
    $default->{'create-new'}       //= ['1'];
    $default->{'quiet'}            //= ['0'];
    $default->{'force'}            //= ['0'];
    $default->{'job-template'}     //= ['-unit-test JenkinsJobTemplate.tt2'];
    $default->{'job-template-var'} //= [];

    # TODO Fix create-new -> create-job or maybe opposite!
    # TODO Check valid values!
    return;
}

sub configure_a_new_job {
    my ( $git, $tpl_filename, %template_vars ) = @_;
    if ( !eval { require Template; } ) {
        $git->error( $PKG, 'Install Module Template (package Template-Toolkit)' . ' to use this plugin!' );
        return;
    }
    my $config = {
        'INCLUDE_PATH' => Path::Tiny::path(q{.})->realpath,
        'ENCODING'     => 'utf8',
        'INTERPOLATE'  => 0,
        'ANYCASE'      => 0,
        'ABSOLUTE'     => 1,
        'RELATIVE'     => 1,
    };
    my $template = Template->new($config);
    my $xml_ready;
    $template->process( $tpl_filename, \%template_vars, \$xml_ready, ) || $git->error( $PKG, $template->error() );
    return $xml_ready;
}

sub trigger_branch {
    my ( $git, $ref ) = @_;
    $log->tracef( 'Entering trigger_branch(%s)', $ref );

    my $cache   = $git->cache($PKG);
    my $jenkins = $cache->{'jenkins'};
    if ( !defined $jenkins ) {
        croak('Internal error: No Jenkins in Git::Hooks cache!');
    }
    my $user = $git->authenticated_user() // '[undefined.user]';

    my %job_names;
    if ( $git->get_config( $CFG => 'project' ) ) {
        $job_names{ $git->get_config( $CFG => 'project' ) } = 'dummy-filename';
    } else {
        %job_names = job_names_and_template_filenames( $git, $ref );
    }

    # If project not exists, create it.
    foreach my $job_name ( keys %job_names ) {
        $log->debugf( 'Handle job (name:%s)', $job_name );

        my $this_job = get_job_from_jenkins( $git, $job_name );
        my %job_info = (
            'description' => $job_name,
            'branch'      => $ref,
        );
        if ( defined $git->get_config( $CFG => 'email-domain' ) ) {
            $job_info{'recipients'} = $user . q{@} . $git->get_config( $CFG => 'email-domain' );
        }
        if ( defined $git->get_config( $CFG => 'override-message-address' ) ) {
            my $overriding_addresses = $EMPTY_STRING;
            my @overrides = $git->get_config( $CFG => 'override-message-address' );
            foreach my $override (@overrides) {
                my ( $refspec, $address ) = split q{ }, $override, 2;
                if ( $ref =~ m/$refspec/msx ) {
                    $overriding_addresses .= length $overriding_addresses > 0 ? $SPACE : $EMPTY_STRING;
                    $overriding_addresses .= $address;
                }
            }

            # Override only if matching branch name was found!
            if ( exists $job_info{'recipients'} && $overriding_addresses ) {
                $job_info{'recipients'} = $overriding_addresses;
            }
        }
        foreach my $var ( $git->get_config( $CFG => 'job-template-var' ) ) {
            my ( $var_name, $var_value ) = split qr/=/msx, $var, 2;
            $job_info{$var_name} = $var_value;
        }
        my $xml_conf = configure_a_new_job( $git, $job_names{$job_name}, %job_info );
        $log->debugf( 'New job: %s', $xml_conf );
        $this_job = $jenkins->create_job( $job_name, $xml_conf );

        # Trigger build
        my $triggered = $jenkins->trigger_build($job_name);
        if ( !defined $triggered ) {
            $git->errorf( $PKG, "Failed to trigger job '%s'.", $job_name );
            if ( $git->get_config( $CFG => 'quiet' ) eq '0' ) {
                print "Failed to trigger job '$job_name'.\n";
            }
            return;
        }
        else {
            if ( $git->get_config( $CFG => 'quiet' ) eq '0' ) {
                print "Job '$job_name' triggered to build.\n";
            }
        }
        $log->debugf('All jobs triggered to Jenkins.');

        # Verify and tell user the status
        my $build_queue = $jenkins->build_queue();
        my $project_url;
        my $why;

        # TODO Write this to handle all jobs triggered by me!
        foreach my $item ( @{ $build_queue->{'items'} } ) {
            if ( $item->{'task'}->{'name'} eq $job_name ) {
                $project_url = $item->{'task'}->{'url'};
                $why         = $item->{'why'};
                last;
            }
        }
        if ( defined $project_url ) {
            print "URL: $project_url\n";
        }
        if ( defined $why ) {
            print "Status: $why\n";
        }
    }
    $log->tracef( 'Exiting trigger_branch():%s', '1' );
    return 1;
}

sub match_regexp_config_item {
    my ( $git, $item_name, $match ) = @_;
    my $item = $git->get_config( $CFG => $item_name );
    if ( $item =~ m/^!/msx ) {
        $log->debugf('Regexp starts with \'!\'. Match with negation!');
        $item = substr $item, 1;    # All string except first character.
        return $match !~ m/$item/msx;
    }
    else {
        return $match =~ m/$item/msx;
    }
}

sub delete_job {
    my ( $git, $ref ) = @_;
    $log->tracef( 'Entering delete_job(%s)', $ref );

    my $cache   = $git->cache($PKG);
    my $jenkins = $cache->{'jenkins'};
    if ( !defined $jenkins ) {
        croak('Internal error: No Jenkins in Git::Hooks cache!');
    }
    my %job_names = job_names_and_template_filenames( $git, $ref );
    foreach my $job_name ( keys %job_names ) {
        my $this_job = get_job_from_jenkins( $git, $job_name );
        if ( defined $this_job ) {

            # Delete the job
            my $deleted = $jenkins->delete_project($job_name);
            if ( !defined $deleted ) {
                $git->error( $PKG, "Failed to delete job '$job_name'!" );
                return;
            }
            if ( $git->get_config( $CFG => 'quiet' ) eq '0' ) {
                print "Job '$job_name' deleted from Jenkins.\n";
            }
        }
        else {
            if ( $git->get_config( $CFG => 'quiet' ) eq '0' ) {
                print "Job '$job_name' not in Jenkins. Not deleted.\n";
            }
        }
    }
    $log->tracef( 'Exiting delete_job():%s', '1' );
    return 1;
}

sub job_names_and_template_filenames {
    my ( $git, $ref ) = @_;
    $log->tracef( 'Entering job_names_and_template_filenames(%s)', $ref );
    my ($branch) = $ref =~ m/^[^\/]+\/[^\/]+\/([[:graph:]]+)$/msx;
    ( my $job_name = $branch ) =~ s/\//-/msx;    # Replace slash-char with dash-char.
    ## no critic (ValuesAndExpressions::ProhibitCommaSeparatedStatements)
    my %job_names = map { $job_name . ( split q{ } )[0], ( split q{ } )[1] } $git->get_config( $CFG => 'job-template' );
    ## use critic (ValuesAndExpressions::ProhibitCommaSeparatedStatements)
    $log->tracef( 'Exiting job_names_and_template_filenames():%s', \%job_names );
    return %job_names;
}

# Get the job/project from Jenkins if it exists.
sub get_job_from_jenkins {
    my ( $git, $job_name ) = @_;
    my $cache   = $git->cache($PKG);
    my $jenkins = $cache->{'jenkins'};
    if ( !defined $jenkins ) {
        croak('Internal error: No Jenkins in Git::Hooks cache!');
    }
    my $jobs = $jenkins->current_status(
        {
            'extra_params' => {
                'tree' => 'jobs[name,color]'
            }
        }
    );
    my $this_job;
    foreach my $job ( @{ $jobs->{'jobs'} } ) {
        if ( $job->{'name'} eq $job_name ) {
            $this_job = $job;
            last;
        }
    }
    return $this_job;
}

# This routine can act as a post-receive hook.
sub handle_affected_refs {
    my ($git) = @_;

    setup_config($git);

    # Connect to Jenkins if not already connected. Check from cache.
    my $cache = $git->cache($PKG);
    if ( !exists $cache->{'jenkins'} ) {
        if ( !eval { require Jenkins::API; } ) {
            $git->error( $PKG, 'Install Module Jenkins::API to use this plugin!' );
            return;
        }
        my %jenkins_config;
        for my $option (qw/base-url api-key api-token/) {
            $jenkins_config{$option} = $git->get_config( $CFG => $option )
              or $git->error( $PKG, "missing $CFG.$option configuration attribute" )
              and return;
        }
        $jenkins_config{'base-url'} =~ s/[\/]{1,}$//msx;    # trim trailing slashes from the URL
        my $jenkins = Jenkins::API->new(
            {
                'base_url' => $jenkins_config{'base-url'},
                'api_key'  => $jenkins_config{'api-key'},
                'api_pass' => $jenkins_config{'api-token'},
            }
        );
        my $jenkins_version = $jenkins->check_jenkins_url();
        if ( !$jenkins_version ) {
            $git->error( $PKG, 'Not able to connect Jenkins at address' . " '$jenkins_config{'base-url'}'!" );
            return;
        }
        else {
            if ( $git->get_config( $CFG => 'quiet' ) eq '0' ) {
                print "Jenkins version: $jenkins_version\n";
            }
        }

        # Set Jenkins in the cache.
        $cache->{'jenkins'} = $jenkins;
    }

    foreach my $ref ( $git->get_affected_refs() ) {
        if ( !is_ref_enabled( $ref, $git->get_config( $CFG => 'ref' ) ) ) {
            if ( $git->get_config( $CFG => 'quiet' ) eq '0' ) {
                print "Ref '$ref' not enabled.\n";
            }
            next;
        }

        my $new_commit = ( $git->get_affected_ref_range($ref) )[1];
        if ( $new_commit =~ m/^[0]{1,}$/msx ) {    # Just zeros, deleted branch.
            delete_job( $git, $ref );
        }
        else {
            my @commit_ids = $git->get_affected_ref_commit_ids($ref);
            $log->debugf( 'commit_ids (from get_affected_ref_commit_ids(%s):%s', $ref, \@commit_ids );
            my $nr_msg_ok_to_trigger = 0;
            foreach my $commit_id (@commit_ids) {
                my $commit_msg = $git->get_commit_msg($commit_id);
                $log->debugf( 'commit message: \'%s\'.', ( substr $commit_msg, 0, $LAST_CHAR_IN_STRING ) );
                if ( !$git->get_config( $CFG => 'allow-commit-msg' ) ) {
                    $log->debugf('No option allow-commit-msg. Allow all.');
                    $nr_msg_ok_to_trigger++;

                    # TODO Shouldn't we have 'last' here?
                }
                if ( match_regexp_config_item( $git, 'allow-commit-msg', $commit_msg ) ) {
                    $log->debugf('Allowed commit msg.');
                    $nr_msg_ok_to_trigger++;

                    # TODO Shouldn't we have 'next' here?
                }
            }
            $log->debugf( 'nr_msg_ok_to_trigger: %s.', $nr_msg_ok_to_trigger );
            if ( $nr_msg_ok_to_trigger > 0 ) {
                trigger_branch( $git, $ref );
            }
        }
    }

    # Disconnect from Jenkins
    $git->clean_cache($PKG);

    return 1;
}

sub handle_commit_at_client {
    my ($git) = @_;

    my $current_branch = $git->get_current_branch();
    if ( !is_ref_enabled( $current_branch, $git->get_config( $CFG => 'ref' ) ) ) {
        if ( $git->get_config( $CFG => 'quiet' ) eq '0' ) {
            print "Ref '$current_branch' not enabled.\n";
        }
        return 1;
    }

    # TODO handle_ref()!
}

# Install hooks
POST_COMMIT \&handle_commit_at_client;
POST_RECEIVE \&handle_affected_refs;
1;

