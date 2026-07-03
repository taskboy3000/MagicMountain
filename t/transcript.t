use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;
use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(write_file read_file);
use Mojo::JSON qw(decode_json);

use_ok('MagicMountain::Model::Transcript');

sub _fresh_file {
    my ($fh, $file) = tempfile(SUFFIX => '.jsonl', UNLINK => 1);
    write_file($file, '');
    return $file;
}

subtest 'log_event appends one JSON line' => sub {
    my $file = _fresh_file();
    my $t = MagicMountain::Model::Transcript->new(file => $file);
    $t->log_event({ type => 'test', narrative => 'hello' });

    my @lines = read_file($file);
    is(scalar @lines, 1, 'one line written');
    my $parsed = eval { decode_json($lines[0]) };
    ok($parsed, 'line is valid JSON');
    is($parsed->{type}, 'test', 'type preserved');
    is($parsed->{narrative}, 'hello', 'narrative preserved');
    ok($parsed->{ts}, 'timestamp added');
};

subtest 'multiple events produce valid JSONL' => sub {
    my $file = _fresh_file();
    my $t = MagicMountain::Model::Transcript->new(file => $file);
    $t->log_event({ type => 'a', narrative => 'first' });
    $t->log_event({ type => 'b', narrative => 'second' });
    $t->log_event({ type => 'c', narrative => 'third' });

    my @lines = read_file($file);
    is(scalar @lines, 3, 'three lines written');
    my $second = decode_json($lines[1]);
    is($second->{type}, 'b', 'second event type preserved');
};

subtest 'file is append-only across instances' => sub {
    my $file = _fresh_file();
    my $t1 = MagicMountain::Model::Transcript->new(file => $file);
    $t1->log_event({ type => 'from_t1', narrative => 'x' });
    undef $t1;

    my $t2 = MagicMountain::Model::Transcript->new(file => $file);
    $t2->log_event({ type => 'from_t2', narrative => 'y' });
    undef $t2;

    my @lines = read_file($file);
    is(scalar @lines, 2, 'both events survive');
    my $first = decode_json($lines[0]);
    is($first->{type}, 'from_t1', 'first event from t1');
};

done_testing;
