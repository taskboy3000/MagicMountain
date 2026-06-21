use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use Test::More;
use File::Temp qw(tempfile tempdir);
use File::Slurp qw(write_file);

use_ok('MagicMountain::Activity::MarketVisit');
use_ok('TestCharacter');

# ── Helpers ──────────────────────────────────────────────────────────

{
    package FakeApp;
    sub new { bless {}, shift }
    sub log { bless {}, 'FakeLogger' }
    sub shed {
        my $self = shift;
        $self->{_shed_items} //= [];
        return $self;
    }
    sub create {
        my ($self, %params) = @_;
        my $item = bless { %params }, 'FakeShedItem';
        push @{ $self->{_shed_items} }, $item;
        return $item;
    }
    sub get {
        my ($self, $id) = @_;
        for my $item (@{ $self->{_shed_items} }) {
            return $item if $item->{id} && $item->{id} eq $id;
        }
        return;
    }
    sub delete {
        my ($self, $id) = @_;
        my @kept;
        for my $item (@{ $self->{_shed_items} }) {
            push @kept, $item unless $item->{id} && $item->{id} eq $id;
        }
        $self->{_shed_items} = \@kept;
    }
    sub transcript { bless {}, 'FakeTranscript' }
    sub find {
        my ($self, $code) = @_;
        my @found;
        for my $item (@{ $self->{_shed_items} }) {
            push @found, $item if $code->($item);
        }
        return \@found;
    }
}
{
    package FakeLogger;
    sub debug { }
    sub info  { }
    sub warn  { }
    sub error { }
    sub fatal { }
}
{
    package FakeShedItem;
    sub getCol { my ($self, $col) = @_; $self->{$col} }
    sub save { 1 }
}
{
    package FakeTranscript;
    sub log_event { 1 }
}

sub _make_content_file {
    my ($fh, $file) = tempfile(SUFFIX => '.yml', UNLINK => 1);
    write_file($file, <<'YAML');
factions:
  - id: syndicate
    name: "The Syndicate"
    interests: [thermal, storage]
    base_multiplier: 1.1
  - id: faculty
    name: "The Faculty"
    interests: [signal, field]
    base_multiplier: 1.0
YAML
    return $file;
}

sub _make_singleton {
    my $content_file = shift;
    my ($fh, $table_file) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($table_file, '{}');

    my $m = MagicMountain::Activity::MarketVisit->new(
        file             => $table_file,
        app              => FakeApp->new,
        content_filename => $content_file,
    );
    $m->load_content;
    return $m;
}

sub _fresh_char {
    TestCharacter->new(
        id            => 'char-1',
        action_points => 15,
        scrap         => 0,
        score         => 0,
    );
}

# ── begin ─────────────────────────────────────────────────────────────

subtest 'begin deducts AP and transitions to negotiating' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = _fresh_char();

    # Add a shed item so begin doesn't die
    my $shed = $m->app->shed;
    my $item = $shed->create(
        id => 'item-1', char_id => 'char-1', artifact_id => 'thermal_box_001',
        behaviors => ['thermal'], decayed_value => 20, original_value => 20,
    );

    srand(42);
    my $result = $m->dispatch($char, 'begin');

    is($m->phase, 'negotiating', 'phase -> negotiating after begin');
    my $v = $result->{view};
    ok($v->{ok}, 'ok is true');
    is($v->{result}, 'negotiating', 'result is negotiating');
    ok($v->{customer}{faction_id}, 'customer has faction_id');
    ok($v->{customer}{faction_name}, 'customer has faction_name');
    is($char->{action_points}, 14, 'AP deducted (15 -> 14)');
};

subtest 'begin dies if no AP' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = TestCharacter->new(action_points => 0, scrap => 0, score => 0);

    eval { $m->dispatch($char, 'begin') };
    like($@, qr/AP exhausted/, 'begin dies on zero AP');
};

subtest 'begin dies if shed is empty' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = _fresh_char();

    eval { $m->dispatch($char, 'begin') };
    like($@, qr/no items in shed/, 'begin dies with empty shed');
};

subtest 'begin from wrong phase dies' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = _fresh_char();

    $m->phase('negotiating');
    eval { $m->dispatch($char, 'begin') };
    like($@, qr/illegal transition/, 'begin from negotiating dies');
};

# ── offer ─────────────────────────────────────────────────────────────

subtest 'offer with matching behavior sells' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = _fresh_char();

    my $shed = $m->app->shed;
    my $shed_item = $shed->create(
        id => 'match-item', char_id => 'char-1', artifact_id => 'thermal_box_001',
        behaviors => ['thermal', 'signal', 'field', 'storage'],
        decayed_value => 20, original_value => 20,
    );

    $m->dispatch($char, 'begin');
    my $result = $m->dispatch($char, 'offer', shed_item_id => 'match-item');

    is($result->{view}{result}, 'sold', 'match -> sold');
    ok($result->{view}{value} > 0, 'positive sale value');
    ok($char->{scrap} > 0, 'scrap awarded');
    ok($char->{score} > 0, 'score awarded');
};

subtest 'offer with mismatched behavior fails' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = _fresh_char();

    my $shed = $m->app->shed;
    $shed->create(
        id => 'mismatch-item', char_id => 'char-1', artifact_id => 'unknown',
        behaviors => ['force'], decayed_value => 30, original_value => 30,
    );

    $m->dispatch($char, 'begin');
    my $result = $m->dispatch($char, 'offer', shed_item_id => 'mismatch-item');

    is($result->{view}{result}, 'no_sale', 'mismatch -> no_sale');
    is($char->{scrap}, 0, 'no scrap awarded');
};

# ── send_away ─────────────────────────────────────────────────────────

subtest 'send_away returns to idle' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = _fresh_char();

    my $shed = $m->app->shed;
    $shed->create(
        id => 'send-item', char_id => 'char-1', artifact_id => 'thermal_box_001',
        behaviors => ['thermal'], decayed_value => 20, original_value => 20,
    );

    $m->dispatch($char, 'begin');
    my $result = $m->dispatch($char, 'send_away');

    is($result->{view}{result}, 'sent_away', 'send_away -> sent_away');
};

done_testing;
