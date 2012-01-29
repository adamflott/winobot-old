package Winobot::Features::Date;

use Winobot::DD;

use Winobot;

sub load {
    my ($class, $id) = @_;

    register_command($id, 'date', \&datetime);

    return;
}

sub datetime {
    return DateTime->now('time_zone' => $ENV{'TZ'})->iso8601;
}

sub unload {
    my ($class, $id) = @_;

    unregister_command($id, 'date', \&datetime);

    return;
}

1;
