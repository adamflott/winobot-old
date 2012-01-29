package Winobot::Features::Insult;

use Winobot::DD;

use Winobot;

my $id;

sub load {
    my ($class, $_id) = @_;

    $id = $_id;

    register_command($id, 'insult', \&insult);

    return;
}

sub insult {
    my ($state) = @_;

    my $db_modify = get_feature_option($id, 'Insult') // {};

    return action($state->args, $db_modify->{'db_modify'} // 0, $state->db->insults, 'insult');
}

sub unload {
    my ($class, $id) = @_;

    unregister_command($id, 'insult', \&insult);

    return;
}

1;
