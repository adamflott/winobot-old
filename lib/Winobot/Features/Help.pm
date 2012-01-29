package Winobot::Features::Help;

use Winobot::DD;

use Winobot;

sub load {
    my ($class, $id) = @_;

    register_command($id, 'help',    \&commands);
    register_command($id, 'enabled', \&enabled);

    return;
}

sub commands {
    my ($state) = @_;

    my @command_names = $state->channel->all_command_names;

    if (@command_names) {
        return 'available commands: ' . join(', ', sort(@command_names));
    }

    return;
}

sub transforms {
    my ($state) = @_;

    my @ret;

    push(@ret, $state->channel->count_decoder_transformers . ' enabled decoder transformers');
    push(@ret, $state->channel->count_encoder_transformers . ' enabled encoder transformers');

    return @ret;
}

sub events {
    my ($state) = @_;

    my @events = $state->channel->all_event_names;

    if (@events) {
        return 'watching events: ' . join(', ', sort(@events));
    }

    return;
}

sub enabled {
    my ($state) = @_;

    return (commands($state), events($state), transforms($state));
}

sub unload {
    my ($class, $id) = @_;

    unregister_command($id, 'help',    \&commands);
    unregister_command($id, 'enabled', \&enabled);

    return;
}

1;
