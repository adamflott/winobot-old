package Winobot::Utils;

use Winobot::DD;

# CPAN
use Class::MOP;
use Class::Unload;
use Math::Random::Secure qw();
use Sub::Exporter;
use Try::Tiny;

# local
use Winobot::Log;

my @funcs_names = qw(
  load_module
  unload_module
  get_random_element
  psc
  parse_sub_command
);

Sub::Exporter::setup_exporter(
    {
        'exports' => \@funcs_names,
        'groups'  => {'default' => \@funcs_names}
    }
);

my $log = Winobot::Log->new;

sub load_module {
    my ($module) = @_;

    my $ret = 1;

    if (Class::MOP::is_class_loaded($module)) {
        return $ret;
    }

    try {
        Class::MOP::load_class($module);

        $log->trace("loaded $module");
    }
    catch {
        $log->error("failed to load $module ", \@_);
        $ret = 0;
    };

    return $ret;
}

sub unload_module {
    my ($module) = @_;

    Class::Unload->unload($module);

    $log->trace("unloaded $module");

    return 1;
}

sub get_random_element {
    my ($items) = @_;

    my $size = scalar(@{$items});

    return unless ($size);

    my $n = Math::Random::Secure::irand($size);

    return $items->[$n];
}

*psc = *parse_sub_command;
sub parse_sub_command {
    my ($request) = @_;

    $request =~ m/(?<command>[^\s]+)(?:\s+(?<args>.*))?/;
    my ($command, $args) = ($+{'command'}, $+{'args'});

    $command =~ s/^\s*//;
    $command =~ s/\s*$//;

    return ($command, $args);
}

1;
