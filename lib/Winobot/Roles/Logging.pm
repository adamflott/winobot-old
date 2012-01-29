package Winobot::Roles::Logging;

use Winobot::DD;

use Moose::Role;

# core
use Scalar::Util qw(blessed);

# local
use Winobot::Log;

# Attributes
has 'log' => (
    'is'         => 'ro',
    'isa'        => 'Winobot::Log',
    'lazy_build' => 1,
);

# Builders
sub _build_log {
    my $self = shift;

    my $log = Winobot::Log->new(
        'set_category' => blessed $self,
        'caller_depth' => 3
    );

    return $log;
}

no Moose::Role;

1;
