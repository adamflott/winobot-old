package Winobot::Features::USATerrorAlertLevel;

use Winobot::DD;

use Winobot;

# CPAN
use AnyEvent::HTTP;
use XML::LibXML;

my $id;

my $pending_work;

sub load {
    my ($class, $_id) = @_;

    $id = $_id;

    register_command($id, 'terror-alert-level', \&terror_alert_level);

    return;
}

sub terror_alert_level_available {
    my ($data, $headers) = @_;

    return unless ($data);

    my $ret;

    undef $pending_work;

    if ($headers->{'Status'} =~ /^2/ && $data !~ /Error/) {
        if ($data) {
            my $dom = XML::LibXML->load_xml(string => $data);

            my @nodes = $dom->getElementsByTagName('THREAT_ADVISORY');

            $ret = $nodes[0]->getAttribute('CONDITION');
        }
    }
    else {
        $ret = 'USATerrorAlertLevel' . $headers->{'Status'} . ' with reason: ' . $headers->{'Reason'};
    }

    my $channel = get_channel($id->[0], $id->[1]);

    my $every_channel = get_channel($channel->on_server_name, '*');

    my $msg = $channel->call_encode_transformers(undef, $every_channel->call_encode_transformers(undef, $ret));

    $channel->public_msg($msg);

    return;
}

sub terror_alert_level {
    my ($state) = @_;

    $pending_work = http_request(
        'GET' => 'http://www.dhs.gov/dhspublic/getAdvisoryCondition',
        \&terror_alert_level_available
    );

    return;
}

sub unload {
    my ($class, $id) = @_;

    unregister_command($id, 'terror-alert-level', \&terror_alert_level);

    undef $id;
    undef $pending_work;

    return;
}

1;
