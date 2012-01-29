package Winobot::Features::SMS;

use Winobot::DD;

use Winobot;
use Winobot::Conf;

# CPAN
use Email::Simple;
use Email::Send;

sub load {
    my ($class, $id) = @_;

    register_command($id, 'addrbook', \&addrbook);
    register_command($id, 'sms',      \&sms);

    return;
}

sub addrbook {
    my ($state) = @_;

    my $args = $state->args;

    $args =~ m/\s*([^\s]+)(?:\s+(.+))?/;

    my ($command, $p) = ($1, $2);

    my $addrs = $state->db->txt;

    $command =~ s/\s//g;

    my @all = $state->db->txt->find->all;

    given ($command) {
        when ('!list') {
            my @r;
            foreach my $addr (@all) {
                push(@r, sprintf('nick: %s, number: %s, email: %s', $addr->{user}, $addr->{number}, $addr->{email}));
            }
            return @r;
        }
        when ('!add') {
            my ($nick, $email, $number) = split(/\s/, $p);

            if ($nick && $email && $number) {
                if ($addrs->insert({'user' => $nick, 'email' => $email, 'number' => $number})) {
                    return sprintf('added nick: %s, email: %s, number: %s', $nick, $email, $number);
                }
            }
        }
        default {
            return "unknown command $_";
        }
    }

    return;
}

sub sms {
    my ($state) = @_;

    my $conf = Winobot::Conf->new;

    my $args = $state->args;

    $args =~ m/^\s*([^\s]+)\s+(.+)/;
    my ($who, $body) = ($1, $2);

    my ($from, undef) = split('!', $state->msg->{prefix});

    my $user = $state->db->txt->find({'user' => $who})->next;

    my $response;

    my $channel_name = $state->channel->name;
    $channel_name =~ s/#//g;

    if (exists($user->{email})) {
        my $email = Email::Simple->create(
            header => [
                To      => $user->{email},
                From    => $from . '@' . $channel_name . '.' . $state->channel->on_server_name,
                Subject => 'Alert!',
            ],
            body => $body
        );

        my $mailer = Email::Send->new(
            {
                mailer      => 'SMTP::TLS',
                mailer_args => [
                    Host     => $conf->data('winobot.smtp.host'),
                    Port     => $conf->data('winobot.smtp.port'),
                    User     => $conf->data('winobot.smtp.auth.user'),
                    Password => $conf->data('winobot.smtp.auth.password'),
                    Hello    => $conf->data('winobot.smtp.hello_domain'),
                ]
            }
        );

        eval { $mailer->send($email) };
        die "Error sending email: $@" if $@;

        if ($@) {
            $response = 'txt not sent to ' . $user->{email};
        }
        else {
            $response = 'txt sent to ' . $user->{email};
        }
    }
    else {
        $response = "$who not found in database";
    }

    return $response;
}

sub unload {
    my ($class, $id) = @_;

    unregister_command($id, 'addrbook', \&addrbook);
    unregister_command($id, 'sms',      \&sms);

    return;
}

1;
