package Winobot::Features::LastSeen;

use Winobot::DD;

use Winobot;

# CPAN
use Time::Duration;

my %seen;

sub load {
    my ($class, $id) = @_;

    register_irc_event($id, 'publicmsg', \&lastseen_record);
    register_command($id, 'lastseen', \&lastseen_command);

    return;
}

sub lastseen_record {
    my ($state) = @_;

    $seen{$state->id->[0] . $state->id->[1]}->{$state->msg->from} = time;

    return;
}

sub lastseen_command {
    my ($state) = @_;

    my $user = $state->args;

    $user =~ s/\s*//g;

    if ($seen{$state->id->[0] . $state->id->[1]}->{$user}) {
        return duration(time() - $seen{$state->id->[0] . $state->id->[1]}->{$user});
    }

    return;
}

sub unload {
    my ($class, $id) = @_;

    unregister_irc_event($id, 'publicmsg', \&lastseen_record);
    unregister_command($id, 'lastseen', \&lastseen_command);

    undef %seen;

    return;
}

1;
