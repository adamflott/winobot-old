package Winobot::Features::Twitter;

use Winobot::DD;

# core
use Encode;
use Time::HiRes qw();

# CPAN
use AnyEvent::Twitter;
use AnyEvent::Twitter::Stream;
use Time::Duration;

# local
use Winobot;
use Winobot::Log;
use Winobot::Utils qw(psc);

my $log = Winobot::Log->new;

my $id;

my ($consumer_key, $consumer_secret, $token, $token_secret, @monitored_users);

# must keep the ref count on the stream listener to function
my $listener;
my $restart_timer;

my %tweets;

my $keep_alive;
my $successful_connection;

sub setup;

sub load {
    my ($class, $_id) = @_;

    $id = $_id;

    setup;
}

sub schedule_restart {
    state $next_scheduled = 2;

    $next_scheduled = $next_scheduled**2;

    $next_scheduled = 0 if ($successful_connection);

    $restart_timer = schedule_task(
        sub {
            undef $listener;
            undef $restart_timer;
            setup;
        },
        $next_scheduled
    );
}

sub setup {
    $consumer_key    = get_feature_option($id, 'Twitter')->{'auth'}->{'consumer'}->{'key'};
    $consumer_secret = get_feature_option($id, 'Twitter')->{'auth'}->{'consumer'}->{'secret'};
    $token           = get_feature_option($id, 'Twitter')->{'auth'}->{'token'}->{'key'};
    $token_secret    = get_feature_option($id, 'Twitter')->{'auth'}->{'token'}->{'secret'};
    @monitored_users = @{get_feature_option($id, 'Twitter')->{'monitor'}};
    @monitored_users = sort(@monitored_users);

    my $ua;

    eval {
        $ua = AnyEvent::Twitter->new(
            'consumer_key'    => $consumer_key,
            'consumer_secret' => $consumer_secret,
            'token'           => $token,
            'token_secret'    => $token_secret
        );
    };

    if ($@) {
        return;
    }

    # The streaming API does not do a screen name to id translation, so we must use the REST API first
    $ua->get('users/lookup', {'screen_name' => join(',', @monitored_users)}, \&stream);

    register_command($id, 'twitter', \&twitter);

    return;
}

sub stream {
    my ($header, $response, $reason) = @_;

    return unless ($response);
    return unless (scalar(@{$response}));

    my @following;

    foreach my $user (@{$response}) {
        my $n = $user->{'screen_name'};
        if (grep { lc($n) eq lc($_) } @monitored_users) {
            push(@following, $user->{'id'});
            $log->info('Will start monitoring user ', $n, ' (id: ', $user->{'id'}, ')');
        }
        else {
            $log->warn('Found user ', $n, ' in response, but not monitoring them, user data is ', $user->{'user'});
        }
    }

    $listener = AnyEvent::Twitter::Stream->new(
        'consumer_key'    => $consumer_key,
        'consumer_secret' => $consumer_secret,
        'token'           => $token,
        'token_secret'    => $token_secret,
        'method'          => 'filter',
        'follow'          => join(',', @following),
        'on_tweet'        => sub {
            my ($tweet) = @_;

            $successful_connection = 1;

            return unless ($tweet && exists($tweet->{'text'}));

            my $user = $tweet->{'user'}->{'screen_name'};
            my $text = $tweet->{'text'};

            # Only show users we are monitoring, not any one who retweets it
            return unless (grep { lc($user) eq lc($_) } @monitored_users);

            # Twitter puts \n in tweets for some weird reason. Observed behavior
            # indicates it's right before a "RT ...". As a result, multiple
            # sends to the IRC server, and result in a invalid command response
            $text =~ s/\r?\n/ /g;

            # Data return causes a nasty:
            #
            #     unhandled callback exception on event \
            #     (send, AnyEvent::IRC::Client=HASH(0x7fbbe98323a8), ARRAY(0x7fbbeb500f20)): \
            #     Wide character in subroutine entry at .../AnyEvent/Handle.pm line 985.
            #
            # that ends up timing out and getting disconnected from the IRC
            # server, therefore we correct the text.
            $text = Encode::encode_utf8($text);

            my $channel = get_channel($id->[0], $id->[1]);

            my $every_channel = get_channel($channel->on_server_name, '*');

            my $msg =
              $channel->call_encode_transformers(undef,
                $every_channel->call_encode_transformers(undef, sprintf('new %s tweet: %s', $user, $text // 'N/A')));

            $channel->public_msg($msg);

            # only keep last tweet for convenience, all others can be fetched from twitter.com
            unshift(@{$tweets{$user}}, $text);
            pop(@{$tweets{$user}}) if (scalar @{$tweets{$user}} > 1);
        },
        'on_keepalive' => sub {
            $keep_alive = Time::HiRes::time;
        },
        'on_error' => sub {
            my ($error) = @_;
            $log->error('received error: ', $error);
            schedule_restart;
        },
        'on_eof' => sub {
            $log->info('eof received');
            schedule_restart;
        },
        'timeout' => 45,
    );

    return;
}

sub twitter {
    my ($state) = @_;

    my ($command, $args) = psc($state->args // '!list');

    given ($command) {
        when ('!list') {
            return join(', ', @monitored_users);
        }
        when ('!last') {
            if ($tweets{$args}) {
                return sprintf('last %s tweet: %s', $args, $tweets{$args}->[0]);
            }
        }
        when ('!status') {
            return 'Last keep alive ' . duration(Time::HiRes::time - $keep_alive);
        }
        default {
            return ('!list shows currently streaming users', '!last <user> shows last tweet from user');
        }
    }

    return;
}

sub unload {
    my ($class, $_id) = @_;

    undef $log;
    undef $id;
    undef $consumer_key;
    undef $consumer_secret;
    undef $token;
    undef $token_secret;
    undef @monitored_users;
    undef $listener;

    unregister_command($_id, 'twitter', \&twitter);

    return;
}

1;
