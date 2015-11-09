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

If set use this Jenkins project instead of extracting the name from ref name.

=head2 githooks.triggerjenkins.create-job [01]

If set to 0, only trigger build if the job already exists.
If set to 1, create a new Jenkins job (project), unless it already exists).
Default 1.

=head2 githooks.triggerjenkins.create-job-template FILENAME

If set, read the file as a L<Template Toolkit|Template> template file,
and use it to create a new Jenkins job. The template needs to create
a job config XML.

=head2 githooks.triggerjenkins.quiet [01]

If set to 1, do not print out anything to explain to user what was done.
If set to 0, explain to user what was done and print out the link
to the Jenkins job.
Default 0.

=head2 githooks.triggerjenkins.force [01]

If set to 1, force a new build by cancelling the running build and scheduling
a new.
Default 0.

=head2 githooks.triggerjenkins.email-domain STRING

The domain name part of email address,
i.e. S<"domain.com"> in S<<user.name@domain.com>>.
If not present, notification email will not be configured into
Jenkins job.

=head1 EXPORTS

This module exports routines that can be used directly without
using all of Git::Hooks infrastructure.

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

my $PKG = __PACKAGE__;
(my $CFG = __PACKAGE__) =~ s/.*::/githooks./msx;

=for Pod::Coverage setup_config configure_a_new_job trigger_branch

=for Pod::Coverage delete_job get_job_from_jenkins job_name

=for stopwords Cxense

=cut

# Hook configuration.
sub setup_config {
    my ($git) = @_;

    my $config = $git->get_config();
    $config->{lc $CFG} //= {};
    my $default = $config->{lc $CFG};

    $default->{'create-new'}   //= [1];
    $default->{'quiet'}        //= [0];
    $default->{'force'}        //= [0];
    $default->{'create-job-template'} //= ['JenkinsJobTemplate.tt2'];

    return;
}

sub configure_a_new_job {
    my ($git, %template_vars) = @_;
    if (! eval { require Template; }) {
        $git->error($PKG, 'Install Module Template (package Template-Toolkit)'
            . ' to use this plugin!');
        return;
    }
    my $config = {
        'INCLUDE_PATH' => Path::Tiny::path(q{.})->realpath,
        'ENCODING' => 'utf8',
        'INTERPOLATE' => 0,
        'ANYCASE' => 0,
        'ABSOLUTE' => 1,
        'RELATIVE' => 1,
    };
    my $template = Template->new($config);
    my $xml_ready;
    $template->process(
        $git->get_config($CFG => 'create-job-template'),
        \%template_vars,
        \$xml_ready,
    ) || $git->error($PKG, $template->error());
    # print Dumper($xml_ready);
    return $xml_ready;
}

sub trigger_branch {
    my ($git, $ref) = @_;

    my $cache = $git->cache($PKG);
    my $jenkins = $cache->{'jenkins'};
    if (!defined $jenkins) {
        croak('Internal error: No Jenkins in Git::Hooks cache!');
    }
    if (! is_ref_enabled($ref, $git->get_config($CFG => 'ref'))) {
        return;
    }
    my $user = $git->authenticated_user();

    my $job_name = job_name($ref);
    my $this_job = get_job_from_jenkins($git, $job_name);

    # If project not exists, create it.
    if (!defined $this_job) {
        my %job_info = (
            'description' => $job_name,
            'branch' => q{*/} . $job_name,
        );
        if (defined $git->get_config($CFG => 'email-domain')) {
            $job_info{'recipients'} = $user . q{@}
                . $git->get_config($CFG => 'email-domain');
        }
        my $xml_conf = configure_a_new_job($git, %job_info);
        $this_job = $jenkins->create_job($job_name, $xml_conf);
    }

    # Trigger build
    my $triggered = $jenkins->trigger_build($job_name);
    if (!defined $triggered) {
        $git->error($PKG, "Failed to trigger job '$job_name'!");
        return;
    }
    print "Job '$job_name' triggered to build.\n";

    # Verify and tell user the status
    my $build_queue = $jenkins->build_queue();
    my $project_url;
    my $why;
    foreach my $item (@{$build_queue->{'items'}}) {
        if ($item->{'task'}->{'name'} eq $job_name) {
            $project_url = $item->{'task'}->{'url'};
            $why = $item->{'why'};
            last;
        }
    }
    if (defined $project_url) {
        print "URL: $project_url\n";
    }
    if (defined $why) {
        print "Status: $why\n";
    }

   return 1;
}

sub delete_job {
    my ($git, $ref) = @_;

    my $cache = $git->cache($PKG);
    my $jenkins = $cache->{'jenkins'};
    if (!defined $jenkins) {
        croak('Internal error: No Jenkins in Git::Hooks cache!');
    }
    my $job_name = job_name($ref);
    my $this_job = get_job_from_jenkins($git, $job_name);
    if (defined $this_job) {
        # Delete the job
        my $deleted = $jenkins->delete_project($job_name);
        if (!defined $deleted) {
            $git->error($PKG, "Failed to delete job '$job_name'!");
            return;
        }
        print "Job '$job_name' deleted from Jenkins.\n";
    } else {
        print "Job '$job_name' not in Jenkins. Not deleted.\n";
    }

   return 1;
}

sub job_name {
    my ($ref) = @_;
    my ($branch) = $ref =~
         m/^[^\/]+\/[^\/]+\/([[:graph:]]+)$/msx;
    (my $job_name = $branch) =~ s/\//-/msx;
    return $job_name;
}

# Get the job/project from Jenkins if it exists.
sub get_job_from_jenkins {
    my ($git, $job_name) = @_;
    my $cache = $git->cache($PKG);
    my $jenkins = $cache->{'jenkins'};
    if (!defined $jenkins) {
        croak('Internal error: No Jenkins in Git::Hooks cache!');
    }
    my $jobs = $jenkins->current_status({
            'extra_params' => {
                'tree' => 'jobs[name,color]'
            }
        });
    my $this_job;
    foreach my $job (@{$jobs->{'jobs'}}) {
        if ($job->{'name'} eq $job_name) {
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
    if (! exists $cache->{'jenkins'}) {
        if (! eval { require Jenkins::API; }) {
            $git->error($PKG, 'Install Module Jenkins::API to use this plugin!');
            return;
        }
        my %jenkins_config;
        for my $option (qw/base-url api-key api-token/) {
            $jenkins_config{$option} = $git->get_config($CFG => $option)
                or $git->error($PKG, "missing $CFG.$option configuration attribute")
                    and return;
        }
        $jenkins_config{'base-url'} =~ s/[\/]{1,}$//msx; # trim trailing slashes from the URL
        my $jenkins = Jenkins::API->new({
          'base_url' => $jenkins_config{'base-url'},
          'api_key'  => $jenkins_config{'api-key'},
          'api_pass' => $jenkins_config{'api-token'},
        });
        my $jenkins_version = $jenkins->check_jenkins_url();
        if (! $jenkins_version) {
            $git->error($PKG, 'Not able to connect Jenkins at address'
                . " '$jenkins_config{'base-url'}'!");
            return;
        }
        else {
            print "Jenkins version: $jenkins_version\n";
        }

        # Set Jenkins in the cache.
        $cache->{'jenkins'} = $jenkins;
    }

    foreach my $ref ($git->get_affected_refs()) {
        if (! is_ref_enabled($ref, $git->get_config($CFG => 'ref'))) {
            next;
        }

        my $new_commit = ($git->get_affected_ref_range($ref))[1];
        if ($new_commit =~ m/^[0]{1,}$/msx) { # Just zeros, deleted branch.
            delete_job($git, $ref);
        } else {
            trigger_branch($git, $ref);
        }
    }

    # Disconnect from Jenkins
    $git->clean_cache($PKG);

    return 1;
}

# Install hooks
POST_RECEIVE     \&handle_affected_refs;
1;

__END__

