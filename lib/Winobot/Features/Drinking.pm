package Winobot::Features::Drinking;

use Winobot::DD;

# core
use FindBin qw();
use File::Path;
use File::Spec;
use File::Basename qw();
use Time::HiRes qw();

# CPAN
use Hailo;
use HTML::Extract;
use Math::Random::Secure qw();
use Roman::Unicode qw(to_roman);
use Text::ASCIITable::Wrap;

# local
use Winobot;
use Winobot::Conf;
use Winobot::Utils;
use Winobot::IRC::Message::Public;

my $id;

my $log = Winobot::Log->new;

my $bac = 0;

my $consumed = 0;

my $start;

my $r = 0.68;       # L/Kg for a male
my $B = 0.00015;    # g/100ml/hr for male

my $weight = 2560;  # 160 pounds

my %sizes = (
    'beer'    => 12,
    'wine'    => 5,
    'spirits' => 1.5,
    'water'   => 8
);

my %unicode_visually_equivalent = (
    'A' => [ 0x00c0, 0x00c1, 0x00c2 ],
    'B' => [ 0x00df, 0x0243, 0x1e04 ],
    'C' => [ 0x0106, 0x0108, 0x010c ],
    'D' => [ 0x0110, 0x010e, 0x018a ],
    'E' => [ 0x0112, 0x0115, 0x0116 ],
    'F' => [ 0xa730, 0x1e1e ],
    'G' => [ 0x0120, 0x011c, 0x01e6 ],
    'H' => [ 0x0124, 0x0126, 0x21e ],
    'I' => [ 0x0130, 0x012c, 0x0197 ],
    'J' => [0x0134],
    'K' => [ 0x0136, 0x0138, 0xa740 ],
    'L' => [ 0x0141, 0x013d ],
    'M' => [ 0x1e3e, 0x043c, 0x0449 ],
    'N' => [ 0x0143, 0x041f, 0x048a ],
    'O' => [ 0x0150, 0x014c, 0x1e4e ],
    'P' => [],
    'Q' => [0x04a8],
    'R' => [ 0x0156, 0x024c, 0x1e5e ],
    'S' => [ 0x0160, 0x015c ],
    'T' => [ 0x0162, 0x0166 ],
    'U' => [ 0x0170, 0x0172, 0x016c ],
    'V' => [0x0194],
    'W' => [0x047e],
    'X' => [ 0x1e8c, 0x04fc ],
    'Y' => [ 0x0176, 0x024e, 0x04af ],
    'Z' => [0x017b],
    'a' => [ 0x0101, 0x0103 ],
    'b' => [ 0x1e07, 0x042c, 0x048d ],
    'c' => [0x0107],
    'd' => [0x0111],
    'e' => [ 0x0113, 0x0117, 0x018f ],
    'f' => [ 0x1e9b, 0x1e9d ],
    'g' => [ 0x0121, 0x011f ],
    'h' => [ 0x0125, 0x043d ],
    'i' => [ 0x0457, ],
    'j' => [0x0458],
    'k' => [ 0x049d, 0x049e, 0x049f ],
    'l' => [],
    'm' => [0x1e3f],
    'n' => [0x0144],
    'o' => [ 0x0151, 0x014d, 0x1e4d ],
    'p' => [0x048f],
    'q' => [ 0x024a, 0x024b ],
    'r' => [ 0x1e5d, 0x0433, 0x0453 ],
    's' => [ 0x0161, 0x015d ],
    't' => [0x0163],
    'u' => [ 0x0171, 0x0173, 0x016f ],
    'w' => [],
    'x' => [ 0x1e8d, 0x0416, 0x04fd ],
    'y' => [ 0x0177, 0x024f, 0x0184 ],
    'z' => [0x017c]
);

my %tasks_burps;
my $task_talkative;
my %tasks_cancel;
my %tasks_misc_action;
my %tasks_vomit;
my $task_sober_up;
my %tasks_commands;

my $data_dir = File::Spec->catdir($FindBin::Bin, 'data', 'markov');

sub load {
    my ($class, $_id) = @_;

    $id = $_id;

    register_command($id, 'drink', \&drink);
    register_command($id, 'bac', sub { return sprintf('%.4f', $bac) });
    register_command($id, 'drinking-consumed', sub { return "I've had $consumed drinks" });

    my $db_modify = get_feature_option($id, 'Drinking') // {};

    if ($db_modify->{'db_modify'} // 0) {
        register_command($id, 'drinking-verbs',   \&drinking_verbs);
        register_command($id, 'drinking-actions', \&drinking_actions);
        register_command($id, 'drinking-sayings', \&drinking_sayings);
    }

    register_transformer($id, 'encoder-priority' => 1, 'encoder' => \&process);

    register_irc_event($id, 'publicmsg', \&trigger_words);

    return;
}

sub unload {
    my ($class, $_id) = @_;

    undef $id;

    unregister_command($id, 'drink', \&drink);
    unregister_command($id, 'bac',   \&bac);

    unregister_command($id, 'drinking-verbs',   \&drinking_verbs);
    unregister_command($id, 'drinking-actions', \&drinking_actions);
    unregister_command($id, 'drinking-sayings', \&drinking_sayings);

    unregister_transformer($id, 'encoder-priority' => 1, 'encoder' => \&process);

    unregister_irc_event($id, 'publicmsg', \&trigger_words);
}

# -------- Begin Random Number Generation --------
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

sub irr {
    my $min = int(shift);
    my $max = int(shift);

    return 0 if ($min == 0 && $max == 0);

    return ir($max - $min + 1) + $min;
}

# -------- End Random Number Generation --------

# -------- Begin Database --------
sub db_interface {
    my ($db, $request) = @_;

    my ($subcommand, $args) = parse_sub_command($request);

    my @reply;

    my ($type, $action) = split(' ', $args, 2);

    $type   //= 'unknown';
    $action //= '';

    my $help_text = '<nick>: !add <type> <action>; !remove <type> <action>; !list <type>; !help';

    given ($subcommand) {
        when ('!help') {
            push(@reply, $help_text);
        }
        when ('!list') {
            my @all = $db->find({'type' => $type})->all;

            my @formatted = split("\n", Text::ASCIITable::Wrap::wrap(join(', ', map { $_->{'action'} } @all), 256));

            push(@reply, @formatted);
        }
        when ('!types') {
            my @all = $db->find->all;

            my %types;
            foreach my $row (@all) {
                $types{$row->{type}} = 1;
            }
            push(@reply, join(', ', sort(keys(%types))));
        }
        when ('!add') {
            if (
                $db->insert(
                    {
                        'type'     => $type,
                          'action' => $action,
                    }
                )
              ) {
                push(@reply, "type: $type action: $action added");
            }
            else {
                push(@reply, "type: $type action: $action failed to add");
            }
        }
        when ('!remove') {
            if (
                $db->remove(
                    {
                        'type'     => $type,
                          'action' => $action
                    }
                )
              ) {
                push(@reply, "type: $type action: $action removed");
            }
            else {
                push(@reply, "type: $type action: $action failed to remove");
            }
        }
        default {
            push(@reply, $help_text->());
        }
    }

    return (scalar @reply == 1) ? $reply[0] : @reply;
}

# -------- End Database --------

# -------- Begin Commands --------
sub drinking_verbs {
    my ($state) = @_;

    return action($state->args, $state->db->drinking_verbs, 'verb');
}

sub drinking_actions {
    my ($state) = @_;

    return db_interface($state->db->drinking_actions, $state->args);
}

sub drinking_sayings {
    my ($state) = @_;

    return db_interface($state->db->drinking_sayings, $state->args);
}

sub drink {
    my ($state) = @_;

    my $request = $state->args // return '';

    my ($command, $args) = parse_sub_command($request);

    my $help_text =
      '!add <classification> <abv_min> <abv_max> <drink name>; where classification is one of: beer, wine, spirits';

    given ($command) {
        when ('!add') {
            my ($classification, $abv_min, $abv_max, $drink_name) = split(/\s+/, $args, 4);

            unless ($classification || $abv_min || $abv_min || $drink_name) {
                return $help_text;
            }

            unless (grep { $classification eq $_ } (keys(%sizes))) {
                return 'classification is one of: beer, wine, spirits';
            }

            $state->db->drink_types->insert(
                {
                    'classification' => $classification,
                    'type'           => $drink_name,
                    'abv_min'        => $abv_min,
                    'abv_max'        => $abv_max
                }
            );

            if ($state->db->last_error->{'err'}) {

                return "failed to add $drink_name: error: " . $state->db->last_error->{'err'};
            }
            else {
                return "$drink_name added";
            }
        }
        when ('!list') {
            my @all = $state->db->drink_types->find->all;

            my @r;

            foreach (@all) {
                push(@r, $_->{'type'});
            }
            return join(', ', sort(@r));
        }
        when ('!help') {
            return $help_text;
        }
    }

    my $name = $request;

    my $drink;

    if ($name eq 'water') {
        $drink = {
            'classification' => 'water',
            'abv_min'        => 0,
            'abv_max'        => 0
        };
    }
    else {
        $drink = $state->db->drink_types->find({'type' => $name})->next;
    }

    unless ($drink) {
        return $help_text;
    }

    if ($consumed == 0) {
        $start = Time::HiRes::time;
        $task_sober_up = schedule_task(\&sober, 1, 3);
    }

    $consumed++;

    # Use Widmark's Basic formula for calculating blood alcohol content
    # formula from: http://breathtest.wsp.wa.gov/SupportDocs%5CStudies_&_Articles%5CWidmarks%20Equation%2003-07-2002.pdf
    my $f = $sizes{$drink->{'classification'}};

    my $z = $f * (rr($drink->{'abv_min'}, $drink->{'abv_max'}) / 100);

    my $c = ($consumed * 0.8 * $z);
    $c = $c / ($weight * $r);

    my $t = Time::HiRes::time() - $start;

    # convert seconds to hours
    $t /= 60;
    $t /= 60;

    $c -= ($B * $t);

    # convert from Kg -> g
    $c *= 100;

    $bac = $c;

    $state->channel->current_brain_name('drinking.brain');

    $log->debug("BAC is now at $bac");

    my @verbs = $state->db->drinking_verbs->find->all;

    my @articles = qw(the some a );

    return join(' ', '/me', get_random_element(\@verbs)->{'verb'}, get_random_element(\@articles), $name);
}

# -------- End Commands --------

# -------- Begin Talking --------
sub get_saying {
    my ($type) = @_;

    my @sayings = get_db_handle->drinking_sayings->find({'type' => $type})->all;

    talk(get_random_element(\@sayings)->{'action'});
}

sub talk_good_saying {
    get_saying('good');
}

sub talk_bad_saying {
    get_saying('bad');
}

sub talk {
    my ($text) = @_;

    return unless ($text);

    my $channel = get_channel($id->[0], $id->[1]);

    $text = mangle_text($text);

    $channel->public_msg($text);
}

sub create_hailo {
    my $p = File::Spec->catfile($data_dir, 'drinking' . '.brain');

    unless (-d $data_dir) {
        File::Path::mkpath($data_dir);
    }

    my $hailo = Hailo->new('storage_class' => 'SQLite', 'brain' => $p);

    return $hailo;
}

sub talkative {
    my $reply = create_hailo->reply;

    return unless $reply;

    while (length($reply) > rr(20, 120)) {
        $reply = substr($reply, 0, rindex($reply, '.'));
    }

    talk($reply);
}

# -------- End Talking --------

# -------- Begin Sobering --------
sub sober {
    $bac -= (r(1) / 500);
    if ($bac <= 0) {
        unschedule_task($task_sober_up);
        $consumed = 0;
        $bac      = 0;
        undef $task_sober_up;
        my $channel = get_channel($id->[0], $id->[1]);

        $channel->current_brain_name($channel->main_brain_name);
    }
}

# -------- End Sobering --------

# -------- Begin Body Functions --------
sub get_action {
    my ($type) = @_;

    my $db = get_db_handle->drinking_actions;

    my @all = $db->find({'type' => $type})->all;

    my $r = get_random_element(\@all);

    return unless (length($r->{'action'}));

    return talk('/me ' . $r->{'action'});
}

sub burp {
    return get_action('burp');
}

sub misc_action {
    return get_action('misc');
}

sub wets_self {
    return get_action('urine');
}

sub vomit {
    return get_action('vomit');
}

# -------- End Body Functions --------

# -------- Begin Scheduling Actions --------
sub schedule_burp {
    my ($unique_id, $limit, $max_bac) = @_;

    $tasks_burps{$unique_id} = schedule_task(
        sub {
            burp;
            unschedule_task($tasks_burps{$unique_id});
            delete $tasks_burps{$unique_id};
        },
        r(2)
    ) if (r > $limit && $bac <= $max_bac);
}

sub schedule_misc_action {
    my ($unique_id, $limit, $max_bac) = @_;

    $tasks_misc_action{$unique_id} = schedule_task(
        sub {
            misc_action;
            unschedule_task($tasks_misc_action{$unique_id});
            delete $tasks_misc_action{$unique_id};
        },
        rr(7, 10)
    ) if (r > $limit && $bac <= $max_bac);
}

sub schedule_vomit {
    my ($unique_id, $limit, $max_bac) = @_;

    $tasks_vomit{$unique_id} = schedule_task(
        sub {
            vomit;
            unschedule_task($tasks_vomit{$unique_id});
            delete $tasks_vomit{$unique_id};
        },
        rr(7, 10)
    ) if (r > $limit && $bac <= $max_bac);
}

# -------- End Scheduling Actions --------

# -------- Begin BAC Handling --------

sub mangle_text {
    my ($text) = @_;

    return $text if ($text =~ m|^/me |);

    $text = mangle_step_1($text);
    $text = mangle_step_2($text);
    $text = mangle_step_3($text);
    $text = mangle_step_4($text);

    return $text;
}

sub mangle_step_1 {
    my ($text) = @_;

    return $text unless ($bac >= 0.10);

    my @s = split('', $text);

    for my $l (@s) {

        next unless ($l);

        # Increase integers
        if ($l =~ m/\d/) {
            my $i = irr(1, 4);
            $i = -$i          if (r > 0.7);
            $l = $i           if (r > 0.92);
            $l = to_roman($l) if (r > 0.95);
        }

        if ($l =~ m/\w/) {

            # Change casing
            $l = uc($l) if (r > 0.95);
            $l = lc($l) if (r > 0.95);

            # Add extra letters
            $l = $l x irr(1, 3) if (r > 0.8);
        }

        # Forget letters
        $l = ' ' if (r > 0.98);
    }
    $text = join('', @s);

    return $text;
}

sub mangle_step_2 {
    my ($text) = @_;

    return $text unless ($bac >= .20);

    my @s = split('', $text // '');
    for my $l (@s) {

        if (r > 0.95 && exists($unicode_visually_equivalent{$l}) && scalar(@{$unicode_visually_equivalent{$l}})) {
            $l = chr(Encode::encode_utf8(get_random_element($unicode_visually_equivalent{$l})));
        }
    }
    $text = join('', @s);

    return $text;
}

sub mangle_step_3 {
    my ($text) = @_;

    return $text unless ($bac >= 0.35);

    my @s = split('', $text // '');
    for my $l (@s) {

        # Change to binary
        $l = sprintf('%b', ord($l)) if (r > 0.98);
    }
    $text = join('', @s);

    return $text;
}

sub mangle_step_4 {
    my ($text) = @_;

    return $text unless ($bac >= 0.40);

    my @s = split('', $text // '');
    for my $l (@s) {

        # Substitute for random characters
        $l .= $l . get_random_element([qw(! @ $ % ^ & * . < > / ? ; : ' " - = + _ )]) if (r > 0.95);
    }

    $text = join('', @s);

    return $text;
}

sub lets_get_this_party_started {
    my ($state) = @_;

    return get_random_element([ $state->db->drinking_trigger_reply->find->all ])->{'reply'};
}

sub trigger_words {
    my ($state) = @_;

    return if ($bac);

    return if ($state->msg->is_me);

    my @words = $state->db->drinking_trigger_words->find->all;

    my $text = $state->args;

    return unless ($text);

    foreach my $word (@words) {
        my $w = $word->{'word'};
        if ($text =~ m/\b$w/i) {
            return lets_get_this_party_started($state);
        }
    }

    return;
}

sub process {
    my ($channel, $state, $text) = @_;

    return unless (defined($text));

    return $text if ($text =~ m|^/me |);

    $log->info("processing $text on ", $channel->name);

    my $t = Time::HiRes::time;

    if ($bac >= 0.01) {

        # Behavior
        #     Average individual appears normal

        my $u = $t + 1;

        talk_good_saying if (r > 0.9 && $bac <= 0.02);

        schedule_burp($t + 1, 0.9, 0.20);
    }

    if ($bac >= 0.03) {

        # Behavior
        #     Mild euphoria
        #     Relaxation
        #     Joyousness
        #     Talkativeness
        #     Decreased inhibition
        # Impairment
        #     Concentration

        my $u = $t + 2;

        talk_good_saying if (r > 0.5 && $bac <= 0.05);

        unless ($task_talkative) {
            $task_talkative = schedule_task(
                sub {
                    talkative if (r > 0.9);
                },
                rr(2, 4),
                5
            );

            $tasks_cancel{$u} = schedule_task(
                sub {
                    unschedule_task($task_talkative);
                    unschedule_task($tasks_cancel{$u});
                    delete $tasks_cancel{$u};
                    undef $task_talkative;
                },
                rr(10, 60)
            );

        }

        schedule_burp($u, 0.5, 0.05);
    }

    if ($bac >= 0.06) {

        # Behavior
        #     Blunted feelings
        #     Disinhibition
        #     Extraversion
        # Impairment
        #     Reasoning
        #     Depth perception
        #     Peripheral vision
        #     Glare recovery

        my $u = $t + 3;

        schedule_misc_action($u, 0.5, 0.09);
    }

    if ($bac >= 0.10) {

        # Behavior
        #     Over-expression
        #     Emotional swings
        #     Anger or sadness
        #     Boisterousness
        #     Decreased libido
        # Impairment
        #     Reflexes
        #     Reaction time
        #     Gross motor control
        #     Staggering
        #     Slurred speech

        # Attempt at simulating mood swings
        talk_good_saying if (r > 0.98 && $bac <= 0.15);
        talk_bad_saying  if (r > 0.98 && $bac <= 0.15);
        talk_good_saying if (r > 0.98 && $bac <= 0.15);
        talk_bad_saying  if (r > 0.98 && $bac <= 0.15);

        $text = mangle_step_1($text);
    }

    if ($bac >= 0.20) {

        # Behavior
        #     Stupor
        #     Loss of understanding
        #     Impaired sensations
        # Impairment
        #     Severe motor impairment
        #     Loss of consciousness
        #     Memory blackout

        my $u = $t + 5;

        # Forget
        $text = '' if (r > 0.95);
    }

    if ($bac >= 0.30) {

        # Behavior
        #     Severe central nervous system depression
        #     Unconsciousness
        #     Death is possible
        # Impairment
        #     Bladder function
        #     Breathing
        #     Heart rate

        my $u = $t + 6;

        wets_self if (r > 0.95);

        # schedule a random command to run
        unless ($tasks_commands{$u}) {
            if (r > 0.8) {
                my @commands = $channel->all_command_names;

                my $command = '';

                do {
                    $command = ir(scalar(@commands));
                } until (grep { !/$command/ } qw(srp config drink));

                $tasks_commands{$u} = schedule_task(
                    sub {
                        my @ret = $channel->call_command($commands[$command], $state);

                        # TODO need to refactor this module to allow multiple $texts as 3rd arg
                        for my $r (@ret) {
                            talk_bad_saying;
                            talk($r);
                        }
                        unschedule_task($tasks_commands{$u});
                        delete $tasks_commands{$u};
                    },
                    rr(1, 10)
                );
            }
        }
    }

    if ($bac >= 0.40) {

        # Behavior
        #     General lack of behavior
        #     Unconsciousness
        #     Death is possible
        # Impairment
        #     Breathing
        #     Heart rate

        my $u = $t + 7;

        $text = mangle_step_2($text);

        talk_bad_saying if (r > 0.95);
    }

    if ($bac >= 0.50) {
        my $u = $t + 8;

        schedule_vomit($u, 0.5, 0.5);
    }

    if ($bac >= 0.75) {
        my $u = $t + 8;

        #   passout;
    }

    return $text;
}

# -------- END BAC Handling --------

1;
