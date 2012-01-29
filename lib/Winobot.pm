package Winobot;

use Winobot::DD;

# core
use File::Basename qw();
use File::Path;
use File::Spec;
use FindBin qw();
use Scalar::Util qw();
use Time::HiRes qw();

# CPAN
use AnyEvent;
use AnyEvent::HTTP;
use AnyEvent::IRC::Client;
use AnyEvent::Worker;
use Hailo;
use List::MoreUtils qw();
use MongoDB;
use Regexp::Common qw(URI);
use Sub::Exporter;
use Text::ASCIITable::Wrap;
use Try::Tiny;

# local
use Winobot::Channel::Manager;
use Winobot::Channel;
use Winobot::Conf;
use Winobot::IRC::Message::Invite;
use Winobot::IRC::Message::Private;
use Winobot::Server;
use Winobot::Server::Manager;
use Winobot::Log;
use Winobot::State;
use Winobot::Utils;

my @funcs_names = qw(
  action
  add_connection
  enable_features
  get_channel
  get_channels
  get_db_handle
  get_feature_option
  get_connection
  get_scheduled_tasks
  load_feature
  loaded_features
  register_command
  register_irc_event
  register_transformer
  schedule_task
  set_feature_option
  unload_feature
  unregister_command
  unregister_irc_event
  unregister_transformer
  unschedule_task
);

Sub::Exporter::setup_exporter(
    {
        'exports' => \@funcs_names,
        'groups'  => {'default' => \@funcs_names}
    }
);

my $conf = Winobot::Conf->new;
my $log  = Winobot::Log->new;

my $cv = AnyEvent->condvar;

my @timers;

my %connections;

my $server_manager = Winobot::Server::Manager->new;

my %channels;

my %pending_work;

my $data_dir = File::Spec->catdir($FindBin::Bin, 'data', 'markov');

# MongoDB
my $conn;
my $db;

my $chanman = Winobot::Channel::Manager->new;

# -------- Begin Connection Handling --------
sub get_connection {
    my ($id) = @_;

    my $name = join('.', ($id->[0], $id->[1]));

    return $connections{$name} // die('no connection found for ', $name);
}

sub add_connection {
    my ($id, $connection) = @_;

    return $connections{join('.', ($id->[0], $id->[1]))} = $connection;
}

# -------- End Connection Handling --------

# -------- Begin Scheduling / Registering : Events, Commands, Transformers --------
sub schedule_task {
    my ($task_cb, $after, $interval) = @_;

    my %args = (
        'after' => $after,
        'cb'    => $task_cb
    );

    if ($interval) {
        $args{'interval'} = $interval;
    }

    my $w = AnyEvent->timer(%args);

    push(@timers, $w);

    $log->info('Scheduled new task to run after ',
        $after, ' seconds', ($interval ? ', every ' . $interval . ' seconds' : ''));

    return $w;
}

sub unschedule_task {
    my $before = scalar(@timers);

    foreach my $timer (@_) {
        @timers = map { (Scalar::Util::refaddr($timer) ne Scalar::Util::refaddr($_)) ? $_ : () } @timers;
    }

    $log->info('unscheduled ', $before - scalar(@timers), ' tasks');

    return $before - scalar(@timers);
}

sub get_scheduled_tasks {
    return @timers;
}

sub register_irc_event {
    my ($id, $event_name, $callback) = @_;

    return get_channel($id->[0], $id->[1])->register_irc_event($event_name, $callback);
}

sub register_transformer {
    my ($id, %args) = @_;

    return get_channel($id->[0], $id->[1])->register_transformer(\%args);
}

sub register_command {
    my ($id, $command_name, $callback) = @_;

    return get_channel($id->[0], $id->[1])->register_command($command_name, $callback);
}

sub unregister_irc_event {
    my ($id, $event_name, $callback) = @_;

    return get_channel($id->[0], $id->[1])->unregister_irc_event($event_name, $callback);
}

sub unregister_transformer {
    my ($id, %args) = @_;

    return get_channel($id->[0], $id->[1])->unregister_transformer(\%args);
}

sub unregister_command {
    my ($id, $command_name, $callback) = @_;

    return get_channel($id->[0], $id->[1])->unregister_command($command_name, $callback);
}

# -------- End Scheduling / Registering : Events, Commands, Transformers --------

# -------- Begin Network Events --------
sub connect {    ## no critic
    my ($server_info, $irc, $err) = @_;

    if (defined $err) {
        $log->error(q(Couldn't connect to server: ), $err);
        return;
    }

    $log->info('Connected to ', $irc->{'host'});

    return;
}

sub disconnect {
    my ($server_info, $irc, $reason) = @_;

    $log->info('disconnected: ', $reason);

    return;
}

sub registered {
    my ($server_info, $irc) = @_;

    $log->debug('registered!');

    $log->debug('will ping server every 60 seconds');

    $irc->enable_ping(60);

    my $state = Winobot::State->new(
        'server_info' => $server_info,
        'db'          => $db,
        'irc'         => $irc,
    );

    return;
}

# -------- End Network Events --------

# -------- Begin Channel Administration Events --------

sub channel_topic {
    my ($server_info, $irc, $channel_name, $topic, $who) = @_;

    $log->info('topic changed on ', $channel_name, ' to ', $topic, ' by ', $who // '?');

    my $channel = get_channel($server_info->{'name'}, $channel_name);

    my $state = Winobot::State->new(
        'id'          => [ $server_info->{'name'}, $channel->name ],
        'server_info' => $server_info,
        'db'          => $db,
        'irc'         => $irc,
        'args'    => {'topic' => $topic, 'who' => $who},
        'channel' => $channel,
    );

    return _handle_returned($channel, _call_irc_event('channel_topic', $channel, $state));
}

sub invite {
    my ($server_info, $irc, $msg) = @_;

    my $parsed = Winobot::IRC::Message::Invite->new($msg);

    my $channel = get_channel($server_info->{'name'}, $parsed->where);

    my $state = Winobot::State->new(
        'id'      => [ $server_info->{'name'}, $channel->name ],
        'db'      => $db,
        'irc'     => $irc,
        'msg'     => $parsed,
        'channel' => $channel,
    );

    return _handle_returned($channel, _call_irc_event('invite', $channel, $state));
}

sub join {    ## no critic
    my ($server_info, $irc, $nick, $channel_name, $is_myself) = @_;

    $log->info($nick, ' joined ', $channel_name);

    my $channel = get_channel($server_info->{'name'}, $channel_name);

    my $state = Winobot::State->new(
        'id'  => [ $server_info->{'name'}, $channel->name ],
        'db'  => $db,
        'irc' => $irc,
        'args' => $is_myself ? 1 : 0,
        'channel' => $channel
    );

    return _handle_returned($channel, _call_irc_event('join', $channel, $state));
}

sub kick {
    my ($server_info, $irc, $kicked_nick, $channel_name, $is_myself, $msg, $kicker_nick) = @_;

    $log->info($kicker_nick, ' kicked ', $kicked_nick, ' from ', $channel_name, ' (', $msg, ')');

    my $channel = get_channel($server_info->{'name'}, $channel_name);

    my $state = Winobot::State->new(
        'id'   => [ $server_info->{'name'}, $channel->name ],
        'db'   => $db,
        'irc'  => $irc,
        'args' => {
            'is_myself'   => $is_myself,
            'msg'         => $msg,
            'kicked_nick' => $kicked_nick,
            'kicker_nick' => $kicker_nick
        },
        'channel' => $channel
    );

    return _handle_returned($channel, _call_irc_event('kick', $channel, $state));
}

sub part {
    my ($server_info, $irc, $nick, $channel_name, $is_myself, $msg) = @_;

    $log->info("part from $nick");

    my $channel = get_channel($server_info->{'name'}, $channel_name);

    my $state = Winobot::State->new(
        'id'  => [ $server_info->{'name'}, $channel->name ],
        'db'  => $db,
        'irc' => $irc,
        'args'    => {'is_myself' => $is_myself, 'msg' => $msg},
        'channel' => $channel
    );

    return _handle_returned($channel, _call_irc_event('part', $channel, $state));
}

# -------- End Channel Administration Events --------

# -------- Begin Chatting Events --------
sub publicmsg {
    my ($server_info, $irc, $channel_name, $msg) = @_;

    my $channel = get_channel($server_info->{'name'}, $channel_name);

    my $state = Winobot::State->new(
        'id'          => [ $server_info->{'name'}, $channel->name ],
        'server_info' => $server_info,
        'db'          => $db,
        'irc'         => $irc,
        'msg'         => $msg,
        'channel'     => $channel,
    );

    my $decoded = $msg->{'params'}->[-1];

    # call global transformers
    my $every_channel = get_channel($server_info->{'name'}, '*');
    $decoded = $every_channel->call_decode_transformers($state, $decoded);

    $decoded = $channel->call_decode_transformers($state, $decoded);

    my @ret;

    $state->msg(Winobot::IRC::Message::Public->new($msg));

    $log->debug('new publicmsg on ', $channel->name, ' ', $decoded // '', ' from ', $state->msg->from);

    if ($decoded) {
        my $my_nick = $server_info->{'nick'};

        if ($state->msg->from eq $my_nick) {
            $state->msg->is_me(1);
        }
        else {
            $state->msg->is_me(0);
        }

        my $addressed = ($decoded =~ m/^\s*${my_nick},/) || 0;

        $state->addressed($addressed);

        if ($addressed) {
            $state->msg->to($my_nick);

            my $addresses_text = $decoded;

            $addresses_text =~ s/^\s*${my_nick}\s*,\s*//;

            my $reply = create_hailo($channel->current_brain_name)->reply($addresses_text);

            while (length($reply) > 100) {

                # TODO better cut off algorithm
                $reply = substr($reply, 0, rindex($reply, '.'));
            }

            push(@ret, $state->msg->from . ': ' . $reply);
        }
        elsif ($decoded =~ m/^\s*${my_nick}:\s*(?<command>[^\s]+)(?:\s+(?<args>.*))?/) {
            my $command = $+{'command'};
            my $args    = $+{'args'};

            $state->args($args);

            $state->msg->is_command(1);

            push(@ret, $channel->call_command($command, $state));
        }
        else {
            $state->msg->is_command(0);

            $state->args($decoded);
        }
    }

    push(@ret, _call_irc_event('publicmsg', $channel, $state));

    my @encoded;

    foreach my $text (@ret) {
        push(@encoded,
            $channel->call_encode_transformers($state, $every_channel->call_encode_transformers($state, $text)));
    }

    return _handle_returned($channel, @encoded);
}

sub privatemsg {
    my ($server_info, $irc, $nick, $ircmsg) = @_;

    my $parsed = Winobot::IRC::Message::Private->new($ircmsg);

    $log->trace('new privatemsg from ', $parsed->from, ': ', $parsed->msg);

    my $channel = get_channel($server_info->{'name'}, $parsed->from);

    my $state = Winobot::State->new(
        'id'          => [ $server_info->{'name'}, $parsed->from ],
        'server_info' => $server_info,
        'db'          => $db,
        'irc'         => $irc,
        'msg'         => $parsed,
        'args'        => $parsed->msg
    );

    return _handle_returned($channel, _call_irc_event('privatemsg', $channel, $state));
}

# -------- End Chatting Events --------

# -------- Begin Private --------
sub _handle_returned {
    my ($channel, @ret) = @_;

    return unless ($channel);

    foreach my $r (@ret) {
        next unless (defined($r) && length($r));

        $channel->public_msg($r);
    }

    return @ret;
}

sub _call_irc_event {
    my ($event_name, $channel, $state) = @_;

    return unless ($channel);

    my @ret = (
        get_channel($channel->on_server_name, '*')->call_events($event_name, $state),
        $channel->call_events($event_name, $state)
    );

    return @ret;
}

# -------- End Private --------

# -------- Begin AI --------
sub create_hailo {
    my ($file_name) = @_;

    $file_name =~ s/\.brain$//;

    my $p = File::Spec->catfile($data_dir, $file_name . '.brain');

    unless (-d $data_dir) {
        File::Path::mkpath($data_dir);
    }

    my $hailo = Hailo->new('storage_class' => 'SQLite', 'brain' => $p);

    return $hailo;
}

sub learn_url {
    my ($state) = @_;

    my ($brain, $url) = split(/\s/, $state->args);

    return '<brain-name> <url>' unless ($brain);

    return $url . ' is not a valid url' unless ($url =~ m/($RE{URI}{HTTP}{-scheme => 'https?'})/);

    $pending_work{$url} = {
        'guard' => http_request(
            'GET' => $url,
            sub {
                my ($data, $headers) = @_;

                http_data_available($data, $headers, $state->channel, $brain);

                return;
            }
        ),
        'brain' => $brain
    };

    return;
}

sub channel_send {
    my ($channel, $text) = @_;

    my $every_channel = get_channel($channel->on_server_name, '*');

    my $msg = $channel->call_encode_transformers(undef, $every_channel->call_encode_transformers(undef, $text));

    return $channel->public_msg($msg);
}

sub http_data_available {
    my ($data, $headers, $channel, $brain) = @_;

    my $info = delete $pending_work{$headers->{'URL'}};

    my $reply;

    if ($headers->{'Status'} =~ /^2/ && $data !~ /Error/) {
        if ($data) {

            my $key = Time::HiRes::time . $brain;

            my $worker = AnyEvent::Worker->new(
                sub {
                    my ($b, $t) = @_;
                    create_hailo($b)->learn($t);
                }
            );

            $worker->do(
                $brain, $data,
                sub {

                    delete $pending_work{$key};

                    if ($@) {
                        $reply = 'failed to train ' . $brain . ' from ' . $headers->{'URL'};
                        channel_send($channel, $reply);
                        return;
                    }

                    $reply = 'trained ' . $brain . ' from ' . $headers->{'URL'} . ' with text length ' . length($data);

                    channel_send($channel, $reply);
                }
            );

            $pending_work{$key} = $worker;
        }
    }
    else {
        $reply = 'MarkovChain error: ' . $headers->{'Status'} . ' with reason: ' . $headers->{'Reason'};
        channel_send($channel, $reply);
    }

    return;
}

# -------- End AI --------

# -------- Begin Utils --------
sub get_channel {
    my ($server_name, $channel_name) = @_;

    #    $log->debug($chanman->all_channels);

    my $found;

    $found = $chanman->find_channel(
        sub {
            ($_ and $_->on_server_name eq $server_name and $_->name eq $channel_name) ? return $_ : return ();
        }
    );

    if (defined $found) {
        $log->trace('found channel ', $found->print_id);
    }
    else {
        $log->warn('found no channel via id ',
            $server_name, ':', $channel_name, ' you probably dont want this unless you are dealing with private chats');

        $found = Winobot::Channel->new(
            'on_server_name' => $server_name,
            'name'           => $channel_name
        );

        $chanman->add_channel($found);
    }

    return $found;
}

sub add_channel {
    my ($server_name, $server_connection, $channel) = @_;

    return $chanman->add_channel($channel);
}

# -------- Begin Feature Handling --------
sub enable_features {
    my $id = shift(@_);

    foreach my $feature (@_) {
        if (load_feature($id, $feature)) {

            my $found = get_channel($id->[0], $id->[1]);

            $found->add_feature($feature);
        }
    }

    return;
}

sub set_feature_option {
    my ($id, $feature_name, $key, $value) = @_;

    if ($key && $value) {
        my ($channel) = get_channel($id->[0], $id->[1]);

        if ($channel) {
            $channel->set_option($feature_name => {$key => $value});

            $log->debug('feature ', $feature_name, ' option set ', $key, ' = ', $value);
        }
    }

    return $value;
}

sub get_feature_option {
    my ($id, $feature_name) = @_;

    my ($channel) = get_channel($id->[0], $id->[1]);

    return $channel->get_feature_option($feature_name);
}

sub loaded_features {
    my @features;

    my @channels = $chanman->all_channels;

    foreach my $channel (@channels) {
        push(@features, $channel->all_features);
    }

    return sort(@{[ List::MoreUtils::uniq(@features) ]});
}

sub load_feature {
    my ($id, $feature) = @_;

    my $channel = get_channel($id->[0], $id->[1]);

    my $ret = 1;

    if ($channel) {
        $ret &= $channel->load_feature($feature);
    }

    $log->trace("called $feature->load return value: $ret");

    return $ret;
}

sub unload_feature {
    my ($id, $feature) = @_;

    my $channel = get_channel($id->[0], $id->[1]);

    $feature = fix_feature_name($feature);

    if ($feature->can('unload')) {
        $feature->unload($id);
    }

    return $channel->unload_feature($feature);
}

sub reload_feature {
    my ($id, $feature) = @_;

    $log->info('Reloading feature: ', $feature);

    return unload_feature($id, $feature) && load_feature($id, $feature);
}

# -------- End Feature Handling --------

# -------- Begin IRC Utilities --------

sub get_channels {
    return $chanman->all_channels;
}

sub action {
    my ($request, $can_modidy_db, $db, $db_key) = @_;

    my ($command, $args) = parse_sub_command($request);

    my @reply;

    given ($command) {
        when ('!help') {
            if ($can_modidy_db) {
                push(@reply, "$db_key <nick>; !add <data>; !remove <data>; !list; !help");
            }
            else {
                push(@reply, "$db_key <nick>");
            }
        }
        when ('!list') {
            my @all = sort $db->find->all;

            my @formatted = split("\n", Text::ASCIITable::Wrap::wrap(CORE::join(', ', @all), 256));

            push(@reply, @formatted);
        }
        when ('!add') {
            if ($can_modidy_db) {
                if (
                    $db->insert(
                        {
                            $db_key => $args
                        }
                    )
                  ) {
                    push(@reply, "$db_key added: $args");
                }
                else {
                    push(@reply, "$db_key failed to add: $args");
                }
            }
        }
        when ('!remove') {
            if ($can_modidy_db) {

                if (
                    $db->remove(
                        {
                            $db_key => $args
                        }
                    )
                  ) {
                    push(@reply, "$db_key removed: $args");
                }
                else {
                    push(@reply, "$db_key failed to remove: $args");
                }
            }
        }
        default {
            my $r = get_random_element([ $db->find->all ]);

            if ($r) {
                push(@reply, $r->{$db_key});

                my $target = $request;

                for (@reply) {
                    if (m/%who%/) {
                        s/%who%/$target/eg;
                    }
                    elsif (!m/\/me\s+/) {
                        $_ = "$target " . $_;
                    }
                }
            }
        }
    }

    return @reply;
}

sub get_db_handle {
    return $db;
}

# -------- End IRC Utilities --------

# -------- Begin Setup / Runner --------

sub run {

    $conn = MongoDB::Connection->new(
        'host' => $conf->data('winobot.database.host'),
        'port' => $conf->data('winobot.database.port')
    );

    $db = $conn->winobot;

    my $servers = $conf->data('winobot.servers');

    $log->info('-' x 80);
    $log->info('Winobot starting up...');

    my $art = << "EOA";
           __
       __ {_/
       \_}\\ _
          _\(_)_
         (_)_)(_)_
        (_)(_)_)(_)
         (_)(_))_)  ____
          (_(_(_)  |    |  ____
           (_)_)   |~~~~| |    |
            (_)    '-..-' |~~~~|
                     ||   '-..-'
                    _||_    ||
                   `""""`  _||_
                          `""""`
EOA

    foreach my $line (split("\n", $art)) {
        $log->info($line);
    }

    $log->info('-' x 80);

    foreach my $name (keys(%{$servers})) {

        my $server = $servers->{$name};

        $server->{'name'} = $name;

        my $pc = AnyEvent::IRC::Client->new;

        $pc->reg_cb(
            'channel_topic' => sub { Winobot::channel_topic($server, @_) },
            'connect'       => sub { Winobot::connect($server,       @_) },
            'disconnect'    => sub { Winobot::disconnect($server,    @_) },
            'irc_invite'    => sub { Winobot::invite($server,        @_) },
            'join'          => sub { Winobot::join($server,          @_) },
            'kick'          => sub { Winobot::kick($server,          @_) },
            'part'          => sub { Winobot::part($server,          @_) },
            'privatemsg'    => sub { Winobot::privatemsg($server,    @_) },
            'publicmsg'     => sub { Winobot::publicmsg($server,     @_) },
            'registered'    => sub { Winobot::registered($server,    @_) },
        );

        my $s = Winobot::Server->new(
            'name'       => $name,
            'host'       => $server->{'host'},
            'port'       => $server->{'port'},
            'nick'       => $server->{'nick'},
            'connection' => $pc
        );

        $s->add_channels($server->{'channels'});

        $server_manager->set_server($name => $s);

        foreach my $channel_name ($s->channel_names) {

            if ($conf->data('winobot.markov_chain.enabled')) {
                register_command([ $s->name, $channel_name ], 'learn-url', \&learn_url);
            }

            add_connection([ $s->name, $channel_name ], $pc);
        }

        $s->connect;
    }

    $cv->wait;

    return;
}

# -------- End Setup / Runner --------

1;
