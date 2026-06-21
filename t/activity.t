use Modern::Perl;

use FindBin;
use lib ("$FindBin::Bin/../lib");

use Test::More;
use File::Temp qw(tempfile);
use Mojo::JSON qw(encode_json);

use_ok('MagicMountain::Activity');

{
    package FakeApp;
    sub new { bless {}, shift }
    sub log { bless {}, 'FakeLogger' }
    sub transcript { bless {}, 'FakeTranscript' }
}
{
    package FakeTranscript;
    sub log_event { 1 }
}
{
    package FakeLogger;
    sub debug { }
    sub info  { }
    sub warn  { }
    sub error { }
    sub fatal { }
}
my $MOCK_APP = FakeApp->new;

my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);

sub _new_activity {
    MagicMountain::Activity->new(
        file        => $file,
        app         => $MOCK_APP,
        content_filename => '/tmp/test_content.yml',
        transitions => { idle => ['begin'], processing => ['push', 'stop'] },
    );
}

# ── Columns ──────────────────────────────────────────────────────────

subtest 'columns include defaults + activity fields' => sub {
    my $a = _new_activity();
    is_deeply(
        $a->columns,
        [qw(id updatedAt createdAt char_id type phase artifact customer)],
        'columns extend defaults with activity fields'
    );
};

subtest 'getCol/setCol work on column fields' => sub {
    my $a = _new_activity();
    $a->setCol('char_id', 'char-123');
    is($a->getCol('char_id'), 'char-123', 'getCol/setCol char_id');
    $a->setCol('type', 'prospecting');
    is($a->getCol('type'), 'prospecting', 'getCol/setCol type');
    $a->setCol('phase', 'processing');
    is($a->getCol('phase'), 'processing', 'getCol/setCol phase');
};

subtest 'artifact column stores hashref' => sub {
    my $a = _new_activity();
    my $hash = { id => 'test_001', value => 42 };
    $a->setCol('artifact', $hash);
    is_deeply($a->getCol('artifact'), $hash, 'artifact column stores hashref');
};

subtest 'customer column stores hashref' => sub {
    my $a = _new_activity();
    my $hash = { faction_id => 'syndicate', irritation => 0 };
    $a->setCol('customer', $hash);
    is_deeply($a->getCol('customer'), $hash, 'customer column stores hashref');
};

# ── Convenience accessors ────────────────────────────────────────────

subtest 'phase accessor defaults to idle' => sub {
    my $a = _new_activity();
    is($a->phase, 'idle', 'phase defaults to idle');
};

subtest 'phase accessor reads persisted value' => sub {
    my $a = _new_activity();
    $a->setCol('phase', 'processing');
    is($a->phase, 'processing', 'phase reads from column');
};

subtest 'phase accessor sets via column' => sub {
    my $a = _new_activity();
    $a->phase('awaiting_buyer');
    is($a->getCol('phase'), 'awaiting_buyer', 'phase setter stores in column');
};

subtest 'artifact accessor round-trip' => sub {
    my $a = _new_activity();
    my $hash = { id => 'x', value => 10 };
    $a->artifact($hash);
    is_deeply($a->artifact, $hash, 'artifact accessor round-trip');
};

subtest 'artifact accessor returns undef when not set' => sub {
    my $a = _new_activity();
    is($a->artifact, undef, 'artifact returns undef when empty');
};

subtest 'customer accessor round-trip' => sub {
    my $a = _new_activity();
    my $hash = { faction_id => 'syndicate', offer => 10 };
    $a->customer($hash);
    is_deeply($a->customer, $hash, 'customer accessor round-trip');
};

# ── Ephemeral attributes ─────────────────────────────────────────────

subtest 'transitions, app, content_filename are Mojo has attributes' => sub {
    my $a = _new_activity();
    is_deeply($a->transitions, { idle => ['begin'], processing => ['push', 'stop'] },
        'transitions attribute');
    is($a->app, $MOCK_APP, 'app attribute');
    is($a->content_filename, '/tmp/test_content.yml', 'content_filename attribute');
    is($a->content_data, undef, 'content_data defaults to undef');
};

subtest 'log attribute delegates to app->log' => sub {
    my $a = _new_activity();
    ok($a->log, 'log attribute exists');
};

# ── Dispatch ─────────────────────────────────────────────────────────

subtest 'dispatch validates transition' => sub {
    my $a = _new_activity();
    $a->phase('idle');

    eval { $a->dispatch({}, 'push') };
    like($@, qr/illegal transition: idle -> push/, 'dispatch dies on illegal push from idle');
};

subtest 'dispatch validates handler exists' => sub {
    my $a = _new_activity();
    $a->phase('idle');

    eval { $a->dispatch({}, 'begin') };
    like($@, qr/no handler for action: begin/, 'dispatch dies when handler missing');
};

done_testing;
