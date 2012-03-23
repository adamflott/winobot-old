package Winobot::Features::LastSeen;

use Winobot::DD;

use Winobot;

# CPAN
use Time::Duration;

sub load {
    my ($class, $id) = @_;

    register_irc_event($id, 'publicmsg',      \&lastseen_record);
    register_irc_event($id, 'channel_change', \&lastseen_record_nick_change);
    register_command($id, 'lastseen', \&lastseen_command);

    return;
}

sub lastseen_record {
    my ($state) = @_;

    $state->db->lastseen->update(
        {
            'id'   => join('.', $state->id->[0], $state->id->[1]),
            'nick' => $state->msg->from
        },
        {'$set'   => {'date' => DateTime->now->epoch}},
        {'upsert' => 1}
    );

    return;
}

sub lastseen_record_nick_change {
    my ($state) = @_;

    $state->db->lastseen->update(
        {
            'id'   => join('.', $state->id->[0], $state->id->[1]),
            'nick' => $state->args->{'old_nick'},
        },
        {
            '$set' => {
                'nick' => $state->args->{'new_nick'},
                'date' => DateTime->now->epoch,
            }
        },
        {'upsert' => 1}
    );

    return;
}

sub lastseen_command {
    my ($state) = @_;

    my $user = $state->args;

    $user =~ s/\s*//g;

    my $r = $state->db->lastseen->find(
        {
            'id'   => join('.', $state->id->[0], $state->id->[1]),
            'nick' => $user
        }
    )->next;

    if ($r) {
        return duration(time() - $r->{'date'});
    }

    return $user . ' not yet seen';
}

sub unload {
    my ($class, $id) = @_;

    unregister_irc_event($id, 'publicmsg',      \&lastseen_record);
    unregister_irc_event($id, 'channel_change', \&lastseen_record_nick_change);
    unregister_command($id, 'lastseen', \&lastseen_command);

    return;
}

1;
