package Winobot::Server;

use Winobot::DD;

use Moose;

with 'Winobot::Roles::Logging';

# core
use Scalar::Util qw();

# CPAN
use Try::Tiny;

# local
use Winobot::Utils;

has 'connection' => (
    'is'       => 'rw',
    'isa'      => 'AnyEvent::IRC::Client',
    'required' => 1
);

has 'name' => (
    'is'       => 'rw',
    'isa'      => 'Str',
    'required' => 1
);

has 'host' => (
    'is'       => 'rw',
    'isa'      => 'Str',
    'required' => 1
);

has 'port' => (
    'is'      => 'rw',
    'isa'     => 'Int',
    'default' => 6667
);

has 'channels' => (
    'traits'  => ['Hash'],
    'is'      => 'rw',
    'isa'     => 'HashRef[Any]',
    'default' => sub { {} },
    'handles' => {
        'set_channel'     => 'set',
        'get_channel'     => 'get',
        'has_no_channels' => 'is_empty',
        'num_channels'    => 'count',
        'delete_channel'  => 'delete',
        'channel_pairs'   => 'kv',
        'channel_names'   => 'keys'
    },
);

has 'nick' => (
    'is'      => 'rw',
    'isa'     => 'Str',
    'default' => 'winobot',
);

has 'user' => (
    'is'      => 'rw',
    'isa'     => 'Str',
    'default' => 'winobot'
);

has 'real' => (
    'is'  => 'rw',
    'isa' => 'Str',

    # Detective
    'default' => 'Dave Cronk'    # Supercop
);

sub connect {
    my ($self) = @_;

    $self->connection->connect(
        $self->host,
        $self->port,
        {
            'nick' => $self->nick,
            'user' => $self->user,
            'real' => $self->real
        }
    );
}

sub disconnect {
    my ($self) = @_;

    $self->connection->disconnect;
}

sub reconnect {
    my ($self) = @_;

    $self->connection->disconnect;
    $self->connect;
}

sub add_channels {
    my ($self, $channels) = @_;

    foreach my $name (keys(%{$channels})) {

        my $channel = $channels->{$name};

        my $c = Winobot::Channel->new(
            'connection'     => $self->connection,
            'on_server_name' => $self->name,
            'name'           => $name,
            'features'       => $channel->{'features'} || [],
        );

        foreach my $o (keys(%{$channel->{'options'}})) {
            $c->set_option($o => $channel->{'options'}->{$o});
        }

        Winobot::add_channel($self->name, $self->connection, $c);

        foreach my $f (keys(%{$channel->{'feature_options'}})) {
            $c->set_feature_option($f => $channel->{'feature_options'}->{$f});
            $self->log->info($f, ' set to ', $channel->{'feature_options'}->{$f});
        }

        $c->load_all_features;

        if ($c->get_option('autojoin')) {

            $self->log->trace('will join ', $c->name);

            $self->connection->send_srv('JOIN', $c->name);
        }

        $self->set_channel($c->name => $channel);
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
