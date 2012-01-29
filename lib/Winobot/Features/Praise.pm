package Winobot::Features::Praise;

use Winobot::DD;

use Winobot;

my $id;

sub load {
    my ($class, $_id) = @_;

    $id = $_id;

    register_command($id, 'praise', \&praise);

    return;
}

sub praise {
    my ($state) = @_;

    my $db_modify = get_feature_option($id, 'Praise') // {};

    return action($state->args, $db_modify->{'db_modify'} // 0, $state->db->praises, 'praise');
}

sub unload {
    my ($class, $id) = @_;

    unregister_command($id, 'praise', \&praise);

    return;
}

1;
