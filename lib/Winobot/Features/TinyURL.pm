package Winobot::Features::TinyURL;

use Winobot::DD;

# CPAN
use AnyEvent::HTTP;
use Regexp::Common qw(URI);

use Winobot;

my $id;

my %pending_urls;

sub load {
    my ($class, $_id) = @_;

    register_irc_event($_id, 'publicmsg', \&tinyize);

    $id = $_id;

    return;
}

sub tiny_url_available {
    my ($data, $headers) = @_;

    return unless ($data);

    my $ret;

    delete $pending_urls{$headers->{'URL'}};

    if ($headers->{'Status'} =~ /^2/ && $data !~ /Error/) {
        if ($data =~ m!(\Qhttp://tinyurl.com/\E\w+)!x) {
            $ret = $data;
            $ret =~ s|^http[s]?://||;
        }
    }
    else {
        $ret = 'TinyURL error: ' . $headers->{'Status'} . ' with reason: ' . $headers->{'Reason'};
    }

    my $channel = get_channel($id->[0], $id->[1]);

    my $every_channel = get_channel($channel->on_server_name, '*');

    my $msg = $channel->call_encode_transformers(undef, $every_channel->call_encode_transformers(undef, $ret));

    $channel->public_msg($msg);

    return;
}

sub tinyize {
    my ($state) = @_;

    return unless $state->args;

    my @matches = ($state->args =~ m/($RE{URI}{HTTP}{-scheme => 'https?'})/g);

    my @urls;

    foreach my $match (@matches) {
        next unless (length($match) > 50);

        $pending_urls{$match} = http_request(
            'GET' => 'http://tinyurl.com/api-create.php' . '?url=' . $match,
            \&tiny_url_available
        );
    }

    return;
}

sub unload {
    my ($class, $_id) = @_;

    unregister_irc_event($_id, 'publicmsg', \&tinyize);

    undef %pending_urls;
    undef $id;

    return;
}

1;
