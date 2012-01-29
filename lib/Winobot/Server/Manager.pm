package Winobot::Server::Manager;

use Winobot::DD;

use Moose;

has 'servers' => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef[Any]',
    default => sub { {} },
    handles => {
        set_server     => 'set',
        get_server     => 'get',
        has_no_servers => 'is_empty',
        num_servers    => 'count',
        delete_server  => 'delete',
        server_pairs   => 'kv',
    },
);

__PACKAGE__->meta->make_immutable;
no Moose;

1;
