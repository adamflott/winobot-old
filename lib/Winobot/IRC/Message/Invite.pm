package Winobot::IRC::Message::Invite;

use Winobot::DD;

use Moose;

extends 'Winobot::IRC::Message';

has [ 'to', 'where', 'from', 'origin' ] => ('is' => 'rw', 'isa' => 'Any');

sub BUILD {
    my ($self, $msg) = @_;

    $self->to($msg->{'params'}->[0]);
    $self->where($msg->{'params'}->[1]);

    $self->command($msg->{'command'});

    my ($from, $origin) = split('!', $msg->{'prefix'});

    $self->from($from);
    $self->origin($origin);

    return;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
