package Winobot::Features::SRP;

use Winobot::DD;

# CPAN
use Algorithm::IRCSRP2::Alice;

# local
use Winobot;
use Winobot::Conf;

my $alice;

my $conf = Winobot::Conf->new;

my $waiting_room_id;

sub load {
    my ($class, $id) = @_;

    register_command($id, 'srp', \&start);

    register_irc_event([ $id->[0], '*' ], 'invite', \&setup_transformer);

    my $config = get_feature_option($id, 'SRP');

    if (exists $config->{'dave'} && length $config->{'dave'}) {
        register_irc_event(
            $id, 'join',
            sub {
                my ($state) = @_;

                return unless $state->args;

                schedule_task(
                    sub {
                        $state->args($config->{'dave'});
                        return start($state);
                    },
                    2.0
                );

                return;
            }
        );
    }

    $waiting_room_id = $id;

    return;
}

sub start {
    my ($state) = @_;

    my $config = get_feature_option($state->id, 'SRP');

    $alice = Algorithm::IRCSRP2::Alice->new('debug_cb' => sub { });

    $alice->I($config->{'user'});
    $alice->P($config->{'password'});

    $alice->init();

    my $receiver = $state->args;

    $receiver =~ s/\s*//g;

    register_irc_event([ $state->server_info->{'name'}, $receiver ], 'privatemsg', \&dave_exchange);

    my $channel = get_channel($state->server_info->{'name'}, $receiver);

    $channel->connection($state->irc);

    $channel->private_msg($receiver, $alice->srpa0);

    $state->log->info('added new alice object to nick: ', $receiver);

    return;
}

sub dave_exchange {
    my ($state) = @_;

    if ($alice) {

        my $data = $state->msg->msg;

        if ($data =~ m/\+srpa1 /) {
            $data =~ s/.*\+srpa1 //;
            my $channel = get_channel($state->server_info->{'name'}, $state->msg->from);

            $channel->connection($state->irc);

            $channel->private_msg($state->msg->from, $alice->verify_srpa1($data));
        }
        elsif ($data =~ m/\+srpa3 /) {
            $data =~ s/.*\+srpa3 //;
            $alice->verify_srpa3($data);
        }
    }
    else {
        $state->log->debug('no alice found for nick: ', $state->msg->from);
    }

    return;
}

sub setup_transformer {
    my ($state) = @_;

    if (get_feature_option($waiting_room_id, 'SRP')->{'encrypted_channel'} eq $state->channel->name) {

        $state->channel->encrypted(1);

        $state->channel->encrypter($alice);

        get_channel($waiting_room_id->[0], $waiting_room_id->[1])->join($state->msg->where);

        register_transformer(
            $state->id,
            'encoder-priority' => 99,
            'decoder-priority' => -1,
            'encoder'          => \&encoder,
            'decoder'          => \&decoder
        );

        unregister_irc_event([ $state->channel->on_server_name, '*' ], 'invite', \&setup_transformer);
    }

    return;
}

sub encoder {
    my ($channel, $state, $decoded) = @_;

    return unless $decoded;

    my $encoded = $alice->encrypt_message($alice->I(), $decoded);

    return $encoded;
}

sub decoder {
    my ($channel, $state, $encoded) = @_;

    return unless $encoded;

    my $decoded = $alice->decrypt_message($encoded);

    return $decoded;
}

1;
