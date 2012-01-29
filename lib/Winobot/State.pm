package Winobot::State;

use Winobot::DD;

use Moose;

with 'Winobot::Roles::Logging';

has 'id' => (
    'is'  => 'rw',
    'isa' => 'ArrayRef[Str]',
);

has 'server_info' => (
    'is'  => 'rw',
    'isa' => 'HashRef',
);

has 'db' => (
    'is'  => 'rw',
    'isa' => 'Any',
);

has 'msg' => (
    'is'  => 'rw',
    'isa' => 'Any',
);

has 'args' => (
    'is'  => 'rw',
    'isa' => 'Any',
);

has 'channel' => (
    'is'  => 'rw',
    'isa' => 'Winobot::Channel',
);

has 'irc' => (
    'is'  => 'rw',
    'isa' => 'AnyEvent::IRC::Client',
);

has 'from_event_name' => (
    'is'  => 'rw',
    'isa' => 'Str',
);

has 'addressed' => (
    'is'  => 'rw',
    'isa' => 'Bool',
);

__PACKAGE__->meta->make_immutable;
no Moose;

1;
