package Winobot::Features::Config;

use Winobot::DD;

# core

# CPAN
use JSON;
use Encode;
use Try::Tiny;

# local
use Winobot;
use Winobot::Conf;
use Winobot::Utils qw(psc);

sub load {
    my ($class, $id) = @_;

    register_command($id, 'config', \&config);
}

sub config {
    my ($state) = @_;

    my ($command, $args) = psc($state->args // '!get');

    my $conf = Winobot::Conf->new;

    given ($command) {
        when ('!get') {
            my $ret;
            try {
                $ret = $conf->data($args);
            }
            catch {
                my ($e) = @_;
                $ret = $e;
            };

            if (ref($ret)) {
                return JSON::encode_json($ret);
            }
            else {
                return $ret;
            }
        }
        when ('!set') {
            my ($key, $value) = split(' ', $args, 2);

            my $data = JSON->new->allow_nonref->utf8->decode(Encode::encode_utf8($value));

            my $rc = $conf->set($key, $data);

            try {
                $rc &= $conf->save('conf/local.yaml');
            };

            if ($rc) {
                return "set: $key = $value";
            }
            else {
                return "set: failed to set $key = $value";
            }
        }
        default {
            return '!get <key>; !set <key> <json-data-structure>';
        }
    }
}

sub unload {
    my ($class, $id) = @_;

    unregister_command($id, 'config', \&config);
}

1;
