package Winobot::BuildConf;

use Moose;

extends 'Thorium::BuildConf';

has '+type' => ('default' => 'irc bot');

has '+files' => ('default' => sub { [] });

__PACKAGE__->meta->make_immutable;
no Moose;

1;
