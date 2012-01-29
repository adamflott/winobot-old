package Winobot::Channel;

use Winobot::DD;

use Moose;

with 'Winobot::Roles::Logging';

# core
use Encode qw();
use Scalar::Util qw();

# CPAN
use Try::Tiny;

# local
use Winobot::Utils;

has 'name' => (
    'is'       => 'rw',
    'isa'      => 'Str',
    'default'  => '?',
    'required' => 1
);

has 'on_server_name' => (
    'is'       => 'rw',
    'isa'      => 'Str',
    'default'  => '?',
    'required' => 1
);

has 'connection' => (
    'is'  => 'rw',
    'isa' => 'AnyEvent::IRC::Client',
);

has 'id' => (
    'is'      => 'rw',
    'isa'     => 'ArrayRef[Str]',
    'default' => sub { [] }
);

has 'encrypted' => (
    'is'      => 'rw',
    'isa'     => 'Bool',
    'default' => 0
);

has 'encrypter' => (
    'is'  => 'rw',
    'isa' => 'Object'
);

has 'options' => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef[Any]',
    default => sub { {} },
    handles => {
        set_option     => 'set',
        get_option     => 'get',
        has_no_options => 'is_empty',
        num_options    => 'count',
        delete_option  => 'delete',
        option_pairs   => 'kv',
    },
);

has 'features' => (
    traits  => ['Array'],
    is      => 'rw',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
    handles => {
        all_features    => 'elements',
        add_feature     => 'push',
        map_features    => 'map',
        filter_features => 'grep',
        find_feature    => 'first',
        join_features   => 'join',
        count_features  => 'count',
        has_features    => 'count',
        has_no_features => 'is_empty',
        sorted_features => 'sort',
    },
);

has 'feature_options' => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef[Any]',
    default => sub { {} },
    handles => {
        set_feature_option     => 'set',
        get_feature_option     => 'get',
        has_no_feature_options => 'is_empty',
        num_feature_options    => 'count',
        delete_feature_option  => 'delete',
        feature_option_pairs   => 'kv',
    },
);

has 'event_handlers' => (
    'traits'  => ['Hash'],
    'is'      => 'rw',
    'isa'     => 'HashRef[ArrayRef[CodeRef]]',
    'default' => sub { {} },
    'handles' => {
        'get_event'       => 'get',
        'set_event'       => 'set',
        'all_events'      => 'elements',
        'has_no_events'   => 'is_empty',
        'all_event_names' => 'keys'
    }
);

has 'transformer_encoder_handlers' => (
    'traits'  => ['Array'],
    'is'      => 'rw',
    'isa'     => 'ArrayRef[HashRef]',
    'default' => sub { [] },
    'handles' => {
        'all_encoder_transformers'   => 'elements',
        'add_encoder_transformer'    => 'push',
        'count_encoder_transformers' => 'count'
    }
);

has 'transformer_decoder_handlers' => (
    'traits'  => ['Array'],
    'is'      => 'rw',
    'isa'     => 'ArrayRef[HashRef]',
    'default' => sub { [] },
    'handles' => {
        'all_decoder_transformers'   => 'elements',
        'add_decodre_transformer'    => 'push',
        'count_decoder_transformers' => 'count'
    }
);

has 'command_handlers' => (
    'traits'  => ['Hash'],
    'is'      => 'rw',
    'isa'     => 'HashRef[ArrayRef[CodeRef]]',
    'default' => sub { {} },
    'handles' => {
        'set_command'       => 'set',
        'get_command'       => 'get',
        'has_no_command'    => 'is_empty',
        'num_commands'      => 'count',
        'all_command_names' => 'keys'
    }
);

has 'main_brain_name' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => 'default.brain'
);

has 'current_brain_name' => (
    'is'  => 'rw',
    'isa' => 'Str',
);

sub BUILD {
    my ($self) = @_;

    $self->id([ $self->on_server_name, $self->name ]);

    $self->current_brain_name($self->main_brain_name);

    return;
}

sub encode {
    my ($self, $msg) = @_;

    my $encoded = $msg;

    if ($self->encrypted) {
        eval { $encoded = $self->encrypter->encrypt_message($self->encrypter->I, $msg); };
    }

    return $encoded;
}

sub decode {
    my ($self, $msg) = @_;

    my $decoded = $msg;

    if ($self->encrypted) {
        eval { $decoded = $self->encrypter->decrypt_message($msg); };
    }

    return $decoded;
}

sub print_id {
    my ($self) = @_;

    return join('.', $self->on_server_name, $self->name);
}

sub _fix_feature_name {
    my ($feature) = @_;

    $feature = 'Winobot::Features::' . $feature unless ($feature =~ m/^Winobot::Features::/);

    return $feature;
}

sub load_feature {
    my ($self, @feature_names) = @_;

    my $ret = 1;
    foreach my $feature (@feature_names) {
        $feature = _fix_feature_name($feature);

        $ret &= load_module($feature);

        if ($ret && $feature->can('load')) {
            $feature->load($self->id);
        }
    }

    return $ret;
}

sub load_all_features {
    my ($self) = @_;

    foreach my $f ($self->all_features) {
        $self->load_feature($f);
    }
}

sub unload_feature {
    my ($self, $feature) = @_;

    $feature = _fix_feature_name($feature);

    if ($feature->can('unload')) {
        $feature->unload($self->id);
    }

    return unload_module($feature);
}

sub register_irc_event {
    my ($self, $event_name, $callback) = @_;

    my $events = $self->get_event($event_name);

    $self->log->info(
        'added coderef at address ',
        Scalar::Util::refaddr($callback),
        ' for event: ', $event_name, ' on ', $self->print_id
    );

    push(@{$events}, $callback);

    $self->set_event($event_name => $events);

    $self->log->debug('registered ', scalar(@{$events}), ' event handlers on ', $self->print_id);

    return scalar(@{$events});
}

sub register_transformer {
    my ($self, $args) = @_;

    $args->{'decoder'} ||= sub { return $_[2] };
    $args->{'encoder'} ||= sub { return $_[2] };
    $args->{'decoder-priority'} //= 0;
    $args->{'encoder-priority'} //= 0;

    my @all_decoders = $self->all_decoder_transformers;
    my @all_encoders = $self->all_encoder_transformers;

    push(@all_decoders, {'decoder' => $args->{'decoder'}, 'decoder-priority' => $args->{'decoder-priority'}});
    push(@all_encoders, {'encoder' => $args->{'encoder'}, 'encoder-priority' => $args->{'encoder-priority'}});

    my @decoders = sort { $a->{'decoder-priority'} <=> $b->{'decoder-priority'} } @all_decoders;
    my @encoders = sort { $a->{'encoder-priority'} <=> $b->{'encoder-priority'} } @all_encoders;

    $self->transformer_encoder_handlers(\@encoders);
    $self->transformer_decoder_handlers(\@decoders);

    $self->log->info(
        'added encoder coderef at address ', Scalar::Util::refaddr($args->{'encoder'}),
        ', decoder coderef at address ',     Scalar::Util::refaddr($args->{'decoder'}),
        ' with decoder priority ',           $args->{'decoder-priority'},
        ' with encoder priority ',           $args->{'encoder-priority'},
        ' for transforer on ',               $self->print_id
    );

    $self->log->debug(
        'registered ',
        $self->count_decoder_transformers + $self->count_encoder_transformers,
        ' transformer handlers on ',
        $self->print_id
    );

    return $self->count_decoder_transformers + $self->count_encoder_transformers;
}

sub register_command {
    my ($self, $command_name, $callback) = @_;

    my $commands = $self->get_command($command_name);

    $self->log->info(
        'added coderef at address ',
        Scalar::Util::refaddr($callback),
        ' for command: ',
        $command_name, ' on ', $self->print_id
    );

    push(@{$commands}, $callback);

    $self->set_command($command_name => $commands);

    $self->log->debug('registered ', scalar(@{$commands}), ' command handlers on ', $self->print_id);

    return scalar(@{$commands});
}

sub unregister_irc_event {
    my ($self, $event_name, $callback) = @_;

    my $handlers = $self->get_event($event_name);

    my $size = scalar(@{$handlers});

    my @filtered =
      map { (Scalar::Util::refaddr($callback) ne Scalar::Util::refaddr($_)) ? $_ : () } @{$handlers};

    $self->set_event($event_name => \@filtered);

    $self->log->info(
        'unregistered ',
        $size - scalar(@filtered),
        ' irc_events for event ',
        $event_name, ' on ', $self->print_id
    );

    return $size - scalar(@filtered);
}

sub unregister_transformer {
    my ($self, $args) = @_;

    my @handlers = $self->all_transformers;

    my $size = scalar(@handlers);

    my @filtered =
      map { (Scalar::Util::refaddr($args->{'encoder'}) ne Scalar::Util::refaddr($_->{'encoder'})) ? $_ : () } @handlers;

    $self->transformer_handlers(\@filtered);

    $self->log->info(
        'unregistered ',
        $size - scalar(@filtered),
        ' transformers for encoder ',
        Scalar::Util::refaddr($args->{'encoder'}),
        ' on ', $self->print_id
    );

    return $size - scalar(@filtered);
}

sub unregister_command {
    my ($self, $command_name, $callback) = @_;

    my $handlers = $self->get_command($command_name);

    my $size = scalar(@{$handlers});

    my @filtered =
      map { (Scalar::Util::refaddr($callback) ne Scalar::Util::refaddr($_)) ? $_ : () } @{$handlers};

    $self->set_command($command_name => \@filtered);

    $self->log->info(
        'unregistered ',
        $size - scalar(@filtered),
        ' commands for event ',
        $command_name, ' on ', $self->print_id
    );

    return $size - scalar(@filtered);
}

sub call {
    my ($self, $kind, $what, $handlers, $state) = @_;

    return unless (scalar(@{$handlers}));

    my @ret;

    my $i = 1;

    $self->log->trace('found ', scalar(@{$handlers}), ' handlers for ', $kind, ' (', $what, ') on ', $self->print_id);

    foreach my $handler (@{$handlers}) {
        try {
            $self->log->trace('calling handler[#', $i, '] for ', $kind, ': ', $what);

            push(@ret, $handler->($state));

            $self->log->trace('called handler[#', $i, '] for ', $kind, ': ', $what, ' and got ', \@ret);
        }
        catch {
            my @e = @_;
            $self->log->cluck('calling ', $what, ' failed: ', @e);
        };

        $i++;
    }

    return @ret;
}

sub call_events {
    my ($self, $event_name, $state) = @_;

    my @ret;

    my $handlers = $self->get_event($event_name) || [];

    return $self->call('event', $event_name, $handlers, $state);
}

sub call_command {
    my ($self, $command_name, $state) = @_;

    my $handlers = $self->get_command($command_name) || [];

    return $self->call('command', $command_name, $handlers, $state);
}

sub call_transformers {
    my ($self, $kind, $handlers, $state, $text) = @_;

    #$self->log->trace('calling all handlers for ', $kind, ' on ', $self->print_id, $handlers);

    for (my $i = 1; $i <= scalar(@{$handlers}); $i++) {

        my $handler = $handlers->[ $i - 1 ];

        try {
            $self->log->trace('calling ', $kind, ' transformer handler[#', $i, '] with text ', q('), $text, q('));

            $text = $handler->{$kind}->($self, $state, $text);

            $self->log->trace('called ', $kind, ' transformer handler[#', $i, '] and got ', q('), $text, q('));
        }
        catch {
            my @e = @_;
            $self->log->cluck('calling ', $kind, ' transformer failed: ', @e);
        };
    }

    return $text;
}

sub call_decode_transformers {
    my ($self, $state, $text) = @_;

    my $handlers = $self->transformer_decoder_handlers || [];

    return $self->call_transformers('decoder', $handlers, $state, $text);
}

sub call_encode_transformers {
    my ($self, $state, $text) = @_;

    my $handlers = $self->transformer_encoder_handlers || [];

    return $self->call_transformers('encoder', $handlers, $state, $text);
}

sub private_msg {
    my ($self, $recipient, $msg) = @_;

    return $self->connection->send_srv('PRIVMSG' => $recipient, $msg);
}

sub public_msg {
    my ($self, $text) = @_;

    $self->log->debug('sending ', $text, ' to ', $self->name);

    my $is_action = ($text =~ m|^/me|) ? 1 : 0;

    if ($self->encrypted) {
        $text = $self->decode($text);
        $is_action = ($text =~ m|^/me|) ? 1 : 0;
    }

    $text = Encode::encode_utf8($text);

    if ($is_action) {
        $text = $self->make_action_string($text);
    }

    if ($self->encrypted) {
        $text = $self->encode($text);
    }

    return $self->connection->send_chan($self->name, 'PRIVMSG', $self->name, $text);
}

sub make_action_string {
    my ($self, $text) = @_;

    $text =~ s/^\/me\s+//;

    return sprintf('%sACTION %s%s', chr(0x01), Encode::encode_utf8($text), chr(0x01));
}

sub join {    ## no critic
    my ($self, $channel_name) = @_;

    $self->log->info('attempting to join ', $channel_name);

    return $self->connection->send_srv('JOIN', $channel_name);
}

sub mode {
    my ($self, $where, $mode, $who) = @_;

    $self->log->debug('sending raw command MODE to ', $where, ' with args ', $mode, ', ', $who);

    $self->connection->send_srv('MODE' => $where, $mode, $who);

    return;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
