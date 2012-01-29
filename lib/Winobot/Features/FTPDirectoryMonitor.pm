package Winobot::Features::FTPDirectoryMonitor;

use Winobot::DD;

# core
use Scalar::Util qw();

# CPAN
use Array::Diff;
use Net::FTP;
use Try::Tiny;

# local
use Winobot;
use Winobot::Log;
use Winobot::Utils qw(psc);

my $log = Winobot::Log->new;

my $id;

my $timer;
my $ftp;

my $monitor_dir;
my @known_completed;

sub load {
    my ($class, $_id) = @_;

    $id = $_id;

    $monitor_dir = get_feature_option($_id, 'FTPDirectoryMonitor')->{'directory'};

    register_command($id, 'content', \&list_last);

    $timer = schedule_task(\&list, 10, 5 * 60);
}

sub list_last {
    my ($state) = @_;

    my ($command, $args) = psc($state->args // '!list');

    given ($command) {
        when ('!list') {
            my $amount = $args || 4;

            unless (scalar(@known_completed)) {
                @known_completed = get_listing();
            }

            my @last_completed = @known_completed;

            @last_completed = sort { $a->{'mtime'} <=> $b->{'mtime'} } @last_completed;

            @last_completed = @last_completed[ -($amount) .. -1 ];

            my @ret = ('last ' . scalar(@last_completed) . ' files on the server:');

            foreach (@last_completed) {
                push(@ret, sprintf(' * %s', $_->{'filename'}));
            }

            return @ret;
        }
        default {
            return ("error: invalid syntax: $command $args", '<nick>: content !list [amount]',
                '[amount] defaults to 4');
        }
    }

    return;
}

sub ftp_connect {
    my ($host, $port, $user, $password) = (
        get_feature_option($id, 'FTPDirectoryMonitor')->{'host'},
        get_feature_option($id, 'FTPDirectoryMonitor')->{'port'},
        get_feature_option($id, 'FTPDirectoryMonitor')->{'user'},
        get_feature_option($id, 'FTPDirectoryMonitor')->{'password'}
    );

    unless ($ftp = Net::FTP->new($host, 'Debug' => 0, 'Port' => $port, 'Timeout' => 10)) {
        $log->error('Failed to connect to ', $host, ':', $port);
        undef $ftp;
        return;
    }

    unless ($ftp->login($user, $password)) {
        $log->error('Failed to login to ', $user, '@', $host, ':', $port);
        undef $ftp;
        return;
    }

    $log->info("FTP connection to $host successful");
}

sub ftp_disconnect {
    if ($ftp) {
        $ftp->quit;

        my $host = get_feature_option($id, 'FTPDirectoryMonitor')->{'host'};
        $log->info("FTP disconnection $host to successful");
    }

    undef $ftp;
}

sub list {

    my @announce = get_listing();

    my $channel = get_channel($id->[0], $id->[1]);

    my $every_channel = get_channel($channel->on_server_name, '*');

    $log->debug('will announce on ', $channel->name);

    foreach my $file (@announce) {
        $log->debug('annoucing new file ', $file, ' on channel ', $channel->name);

        my $msg =
          $channel->call_encode_transformers(
            undef,
            $every_channel->call_encode_transformers(undef, sprintf('New content: %s', $file)));

        $channel->public_msg($msg);
    }
}

sub get_listing {

    ftp_connect;

    my @completed;

    return unless ($ftp);

    unless (@completed = $ftp->ls($monitor_dir)) {
        $log->error('Failed to get dir listing with error: ', $ftp->message);
        return;
    }

    @completed = grep { !($_ =~ m/^\.{1,2}$/ || $_ =~ m/.meta$/i) } @completed;
    @completed = sort(@completed);

    # $log->debug('all files ', join(', ', map { qq('$_') } @completed));

    my @announce;

    if (@known_completed == 0) {
        @known_completed = @completed;
    }
    else {
        my $diff = Array::Diff->diff(\@known_completed, \@completed);

        $log->info('found ', $diff->count, ' new completed files');

        my @new = @{$diff->added};

        push(@announce, @new);

        @known_completed = @completed;
    }

    ftp_disconnect;

    return @announce;
}

sub unload {
    unschedule_task($timer);

    unregister_command('content', \&list_last);

    undef @known_completed;

    undef $log;
    undef $timer;
    undef $id;

    undef $ftp;
}

1;
