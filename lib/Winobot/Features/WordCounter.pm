package Winobot::Features::WordCounter;

use Winobot::DD;

# CPAN
use DateTime;

use Winobot;

sub load {
    my ($class, $id) = @_;

    my $to_count = get_feature_option($id, 'WordCounter') || [];

    foreach my $word (@{$to_count}) {
        register_command(
            $id,
            $word->{'command'},
            sub {
                my ($state) = @_;

                return _stat_count($state->db, $word->{'command'});
            }
        );
    }

    register_irc_event($id, 'publicmsg', \&count);

    return;
}

sub count {
    my ($state) = @_;

    my $text = $state->args;

    my $to_count = get_feature_option($state->id, 'WordCounter') || [];

    foreach my $word (@{$to_count}) {

        next unless ($text);

        my $regex   = $word->{'regex'};
        my $command = $word->{'command'};

        my @matches = ($text) =~ m/$regex/g;

        for (@matches) {
            next if (m/\b$command/);

            _stat_update($state->db, $word->{'command'});
        }
    }

    return;
}

sub _stat_update {
    my ($db, $key) = @_;

    my $counter = $db->chanstats;

    my $count = $counter->update(
        {'key' => $key, 'date' => DateTime->now('time_zone' => $ENV{'TZ'})->ymd},
        {'$inc'   => {'value' => 1}},
        {'upsert' => 1}
    );
    
    return;
}

sub _stat_count {
    my ($db, $key) = @_;

    my $counter = $db->chanstats;

    my $count = $counter->find({'key' => $key, 'date' => DateTime->now('time_zone' => $ENV{'TZ'})->ymd})->next;
    my @total = $counter->find({'key' => $key})->all;

    my $total = 0;

    foreach my $r (@total) {
        $total += $r->{'value'};
    }

    if (@total) {
        return sprintf('today: %d, total: %d, day average: %.2f', $count->{'value'} // 0, $total, ($total / scalar(@total)));
    }
    else {
        return 'none found!';
    }
}

sub unload {
    my ($class, $id) = @_;

    unregister_irc_event($id, 'publicmsg', \&count);

    return;
}

1;
