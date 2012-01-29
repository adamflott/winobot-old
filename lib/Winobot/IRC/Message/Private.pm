package Winobot::IRC::Message::Private;

use Winobot::DD;

use Moose;

extends 'Winobot::IRC::Message';

has [ 'to', 'msg', 'from', 'origin' ] => ('is' => 'rw', 'isa' => 'Any');

sub BUILD {
    my ($self, $msg) = @_;

    $self->to($msg->{'params'}->[0]);
    $self->msg($msg->{'params'}->[1]);

    $self->command($msg->{'command'});

    my ($from, $origin) = split('!', $msg->{'prefix'});

    $self->from($from);
    $self->origin($origin);

    return;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
