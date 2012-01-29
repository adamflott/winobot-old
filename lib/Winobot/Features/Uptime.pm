package Winobot::Features::Uptime;

use Winobot::DD;

use Winobot;

# CPAN
use Time::Duration;

sub load {
    my ($class, $id) = @_;

    register_command($id, 'uptime', \&uptime);

    return;
}

sub uptime {
    return duration(time() - $^T);
}

sub unload {
    my ($class, $id) = @_;

    unregister_command($id, 'uptime', \&uptime);

    return;
}

1;
