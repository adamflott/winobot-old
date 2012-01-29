package Winobot::Features::Random;

use Winobot::DD;

# CPAN
use Math::Random::Secure qw();

# local
use Winobot;
use Winobot::Utils;

sub r {
    return Math::Random::Secure::rand(shift);
}

sub ir {
    return Math::Random::Secure::irand(shift);
}

sub rr {
    my ($min, $max) = @_;

    return 0 if ($min == 0 && $max == 0);

    return r($max - $min + 1) + $min;
}

sub load {
    my ($class, $id) = @_;

    register_command($id, 'random', \&random);
}

sub random {
    my ($state) = @_;

    my $request = $state->args // '';

    my ($subcommand, $args) = parse_sub_command($request);

    $args //= '';

    my $help_text = 'usage: <!n | !f | !one> [args]';

    given ($subcommand) {
        when ('!n') {
            my ($min, $max) = split(/\s/, $args);

            return int(rr($min // 0, $max // 10));
        }
        when ('!f') {
            my ($min, $max) = split(/\s/, $args);

            return rr($min // 0, $max // 10);
        }
        when ('!one') {
            my @items = split(/\s/, $args);
            return get_random_element(\@items);
        }
        default {
            return $help_text;
        }
    }

    return $help_text;
}

sub unload {
    my ($class, $id) = @_;

    unregister_command($id, 'random', \&random);
}

1;
