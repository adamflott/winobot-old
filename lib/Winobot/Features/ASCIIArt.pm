package Winobot::Features::ASCIIArt;

use Winobot::DD;

# core
use FindBin;
use File::Spec;

# CPAN
use File::Slurp qw(read_dir read_file);

# local
use Winobot;
use Winobot::Utils qw(get_random_element);

my $data_dir = File::Spec->catdir($FindBin::Bin, 'data', 'ascii-art');

sub load {
    my ($class, $id) = @_;

    register_command($id, 'art', \&art);
}

sub art {
    my ($state) = @_;

    my @files = read_dir($data_dir);

    @files = grep { /\.txt$/ } @files;

    my $file = get_random_element(\@files);

    my $text = read_file(File::Spec->catfile($data_dir, $file));

    return split(/\n/, $text);
}

sub unload {
    my ($class, $id) = @_;

    unregister_command($id, 'art', \&arg);

    undef $data_dir;
}

1;
