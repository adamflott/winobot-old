package Winobot::Channel::Manager;

use Winobot::DD;

use Moose;

has 'channels' => (
    traits  => ['Array'],
    is      => 'rw',
    isa     => 'ArrayRef[Winobot::Channel]',
    default => sub { [] },
    handles => {
        all_channels    => 'elements',
        add_channel     => 'push',
        map_channels    => 'map',
        filter_channels => 'grep',
        find_channel    => 'first',
        join_channels   => 'join',
        count_channels  => 'count',
        has_channels    => 'count',
        has_no_channels => 'is_empty',
        sorted_channels => 'sort',
    },
);

__PACKAGE__->meta->make_immutable;
no Moose;

1;
