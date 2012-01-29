package Winobot::Features::URLSaver;

use Winobot::DD;

# CPAN
use Regexp::Common qw /URI/;

# local
use Winobot;
use Winobot::Utils qw(get_random_element);

sub load {
    my ($class, $id) = @_;

    register_irc_event($id, 'publicmsg', \&save_url);
    register_command($id, 'url', \&get_url);

    return;
}

sub save_url {
    my ($state) = @_;

    return unless $state->args;

    my @matches = ($state->args =~ m/($RE{URI}{HTTP}{-scheme => 'https?'})/g);

    my @urls;

    foreach my $match (@matches) {
        $state->db->urls->insert({'url' => $match});
    }

    return;
}

sub get_url {
    my ($state) = @_;

    my @urls = $state->db->urls->find->all;

    my $u = get_random_element(\@urls);

    return $u->{'url'};
}

sub unload {
    my ($class, $id) = @_;

    unregister_irc_event($id, 'publicmsg', \&save_url);
    unregister_command($id, 'url', \&get_url);

    return;
}

1;
