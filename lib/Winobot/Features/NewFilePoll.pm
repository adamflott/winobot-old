package Winobot::Features::NewFilePoll;

use Winobot::DD;

# core
use File::Spec;

# CPAN
use AnyEvent::Worker;
use Array::Diff;
use File::Find::Rule;

# local
use Winobot;
use Winobot::Log;
use Winobot::Utils qw(psc);

my $log = Winobot::Log->new;

my $id;
my $worker;
my $timer;
my %timers;

my @poll_dirs;
my @known_completed;

sub load {
    my ($class, $_id) = @_;

    $id = $_id;

    @poll_dirs = @{get_feature_option($_id, 'NewFilePoll')->{'directories'}};

    register_command($id, 'files', \&files);

    $worker = AnyEvent::Worker->new(
        sub {
            my $thirty_mins_ago = time - 30 * 60;

            my @dirs = map { $_->{'dir'} } @poll_dirs;

            my @completed = File::Find::Rule->file->size('>0')->mtime("<=$thirty_mins_ago")->in(@dirs);

            return @completed;
        }
    );

    $timer = schedule_task(\&list, 10, 10 * 60);
}

sub files {
    return "Known files: " . scalar @known_completed;
}

sub list {

    for (@poll_dirs) {
        return unless (-d $_->{'dir'});
    }

    $worker->do(\&announce);

    return;
}

sub announce {
    my ($w, @completed) = @_;

    if ($@) {
        warn $@;
        return;
    }

    @completed = grep { !($_ =~ m/^\.{1,2}$/ || $_ =~ m/.meta$/i) } @completed;
    @completed = sort(@completed);

    foreach my $dir (@poll_dirs) {
        @completed = map {
            my $d    = $_;
            my $root = $dir->{'root'};
            if (m/^${root}/) {
                $d = File::Spec->abs2rel($_, $root);
            }
            $d;
        } @completed;
    }

    my @announce;

    if (@known_completed == 0) {
        @known_completed = @completed;
    }
    else {
        my $diff = Array::Diff->diff(\@known_completed, \@completed);

        $log->debug('found ', $diff->count, ' new completed files');

        my @new = @{$diff->added};

        my $channel = get_channel($id->[0], $id->[1]);

        my $every_channel = get_channel($channel->on_server_name, '*');

        $log->debug('will announce on ', $channel->name);

        my $t = 0.0;

        foreach my $file (@new) {

            $log->debug('annoucing new file ', $file, ' on channel ', $channel->name);

            my $msg = $channel->call_encode_transformers(undef, $every_channel->call_encode_transformers(undef, sprintf('New content: %s', $file)));

            $t *= 2;

            $timers{$msg} = schedule_task(
                sub {
                    $channel->public_msg($msg);
                    delete $timers{$msg};
                    return;
                },
                $t
            );
        }

        @known_completed = @completed;
    }

    return;
}

sub unload {
    unschedule_task($timer);

    unregister_command($id, 'files', \&files);

    undef @known_completed;

    undef $log;
    undef $timer;
    undef %timers;
    undef $id;
    undef $worker;
}

1;
