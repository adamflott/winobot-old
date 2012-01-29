package Winobot::Features::Echo;

use Winobot::DD;

use Winobot;

sub load {
    my ($class, $id) = @_;

    register_command($id, 'echo', \&echo);

    return;
}

sub echo {
    return shift->args;
}

sub unload {
    my ($class, $id) = @_;

    unregister_command($id, 'echo', \&echo);

    return;
}

1;
