package Winobot::IRC::Message::Public;

use Winobot::DD;

use Moose;

extends 'Winobot::IRC::Message';

has [ 'channel_name', 'msg', 'from', 'origin', 'to', 'is_me', 'is_command' ] => ('is' => 'rw', 'isa' => 'Any');

sub BUILD {
    my ($self, $msg) = @_;

    $self->channel_name($msg->{'params'}->[0]);
    $self->msg($msg->{'params'}->[1]);

    $self->command($msg->{'command'});

    my ($from, $origin) = split('!', $msg->{'prefix'});

    $self->from($from);
    $self->origin($from);

    return;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
