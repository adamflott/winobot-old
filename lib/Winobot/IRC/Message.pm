package Winobot::IRC::Message;

use Winobot::DD;

use Moose;

has ['command'] => ('is' => 'rw', 'isa' => 'Any');

__PACKAGE__->meta->make_immutable;
no Moose;

1;
