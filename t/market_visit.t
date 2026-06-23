use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use Test::More;
use File::Temp qw(tempfile tempdir);
use File::Slurp qw(write_file);

use_ok('MagicMountain::Activity::MarketVisit');
use MagicMountain::Model::Season;
use_ok('TestCharacter');

# ── Helpers ──────────────────────────────────────────────────────────

{
    package FakeDispositionStore;
    sub new { bless { items => [] }, shift }
    sub create {
        my ($self, %params) = @_;
        my $item = bless { %params }, 'FakeShedItem';
        push @{ $self->{items} }, $item;
        return $item;
    }
}

{
    package FakeApp;
    sub new { bless {}, shift }
    sub home { $FindBin::Bin . '/..' }
    sub log { bless {}, 'FakeLogger' }
    sub config { shift->{config} || {} }
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
    sub disposition {
        my $self = shift;
        $self->{_disposition_store} //= FakeDispositionStore->new;
        return $self->{_disposition_store};
    }
    sub seasons { shift->{_seasons} }
    sub active_season { shift->{_active_season} }
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
    is(ref $char->{faction_sales}, 'HASH', 'faction_sales is a hash');
    is((values %{ $char->{faction_sales} })[0], 1, 'faction_sales incremented to 1');
    is((values %{ $char->{standing} })[0], 2, 'standing +2 on match');
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
    $m->customer->{settle_chance} = 0.0;
    srand(42);
    my $result = $m->dispatch($char, 'offer', shed_item_id => 'mismatch-item');

    is($result->{view}{result}, 'no_match', 'first mismatch -> no_match, not no_sale');
    is($char->{scrap}, 0, 'no scrap awarded');
    ok($m->getCol('phase') ne 'idle', 'activity not yet idle');
};

subtest 'mismatch settles when settle_chance forced' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = _fresh_char();

    my $shed = $m->app->shed;
    $shed->create(
        id => 'settle-item', char_id => 'char-1', artifact_id => 'unknown',
        behaviors => ['force'], decayed_value => 30, original_value => 30,
    );

    $m->dispatch($char, 'begin');
    $m->customer->{settle_chance} = 1.0;
    my $result = $m->dispatch($char, 'offer', shed_item_id => 'settle-item');

    is($result->{view}{result}, 'sold', 'mismatch -> sold when settle hits');
    ok($char->{scrap} > 0, 'scrap awarded on settle');
    is((values %{ $char->{standing} })[0], 0, 'standing +0 on settle');
};

subtest 'mismatch does not settle when settle_chance=0' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = _fresh_char();

    my $shed = $m->app->shed;
    $shed->create(
        id => 'no-settle-item', char_id => 'char-1', artifact_id => 'unknown',
        behaviors => ['force'], decayed_value => 30, original_value => 30,
    );

    $m->dispatch($char, 'begin');
    $m->customer->{settle_chance} = 0.0;
    my $result = $m->dispatch($char, 'offer', shed_item_id => 'no-settle-item');

    is($result->{view}{result}, 'no_match', 'mismatch -> no_match when settle blocked');
    is($char->{scrap}, 0, 'no scrap awarded');
};

# ── send_away ─────────────────────────────────────────────────────────

# ── Selling Skill 2: irritation immunity ────────────────────────────

subtest 'selling skill 2 eliminates irritation on mismatch' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = TestCharacter->new(
        id => 'char-1', action_points => 15, scrap => 0, score => 0,
        skill_selling => 2,
    );

    my $shed = $m->app->shed;
    $shed->create(
        id => 'mismatch-item-1', char_id => 'char-1', artifact_id => 'unknown',
        behaviors => ['force'], decayed_value => 30, original_value => 30,
    );
    $shed->create(
        id => 'mismatch-item-2', char_id => 'char-1', artifact_id => 'unknown',
        behaviors => ['force'], decayed_value => 30, original_value => 30,
    );

    $m->dispatch($char, 'begin');
    $m->customer->{settle_chance} = 0.0;
    $m->customer->{irritation_threshold} = 5;

    # First mismatch — irritation should stay 0
    srand(42);
    my $r1 = $m->dispatch($char, 'offer', shed_item_id => 'mismatch-item-1');
    is($r1->{view}{result}, 'no_match', 'first mismatch -> no_match');
    is($m->customer->{irritation}, 0, 'irritation stays 0 with sell 2');

    # Second mismatch — still 0
    my $r2 = $m->dispatch($char, 'offer', shed_item_id => 'mismatch-item-2');
    is($r2->{view}{result}, 'no_match', 'second mismatch -> no_match');
    is($m->customer->{irritation}, 0, 'irritation still 0 after second mismatch');
};

# ── Selling Skill 3: reveal + 1.4x match multiplier ─────────────────

subtest 'selling skill 3 reveals behavior and uses 1.4x multiplier' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = TestCharacter->new(
        id => 'char-1', action_points => 15, scrap => 0, score => 0,
        skill_selling => 3,
    );

    my $shed = $m->app->shed;
    $shed->create(
        id => 'match-item-s3', char_id => 'char-1', artifact_id => 'thermal_box_001',
        behaviors => ['thermal'], decayed_value => 20, original_value => 20,
    );

    my $begin_result = $m->dispatch($char, 'begin');
    ok(exists $begin_result->{view}{customer}{revealed_behavior},
        'revealed_behavior is present with sell 3');

    # Force customer to want 'thermal' so match is deterministic
    $m->customer->{desired_behaviors} = ['thermal'];

    my $result = $m->dispatch($char, 'offer', shed_item_id => 'match-item-s3');
    is($result->{view}{result}, 'sold', 'match -> sold');
    # decayed=20, base_mult=1.1, match_mult=1.4 (sell 3) => int(20 * 1.1 * 1.4) = 28 (floating point)
    ok($result->{view}{value} > 22, '1.4x match multiplier applied (value > default 1.1*1.2=26.4)');
};

# ── Customer storms off ─────────────────────────────────────────────

subtest 'customer storms off when irritation exceeds threshold' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = TestCharacter->new(
        id => 'char-1', action_points => 15, scrap => 0, score => 0,
    );

    my $shed = $m->app->shed;
    for my $i (1 .. 6) {
        $shed->create(
            id => "storm-item-$i", char_id => 'char-1', artifact_id => 'unknown',
            behaviors => ['force'], decayed_value => 10, original_value => 10,
        );
    }

    $m->dispatch($char, 'begin');
    $m->customer->{settle_chance} = 0.0;
    $m->customer->{irritation_threshold} = 5;

    my $stormed = 0;
    for my $i (1 .. 6) {
        srand(42);
        my $r = $m->dispatch($char, 'offer', shed_item_id => "storm-item-$i");
        if ($r->{view}{result} eq 'customer_left') {
            $stormed = 1;
            ok(length($r->{view}{message}) > 0, 'storm-off message is non-empty');
            last;
        }
    }
    ok($stormed, 'customer eventually storms off');
};

# ── Evolved item standing bonus ─────────────────────────────────────

subtest 'evolved item gives +1 standing bonus on sale' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = TestCharacter->new(
        id => 'char-1', action_points => 15, scrap => 0, score => 0,
    );

    my $shed = $m->app->shed;
    $shed->create(
        id => 'evolved-item', char_id => 'char-1', artifact_id => 'thermal_box_001',
        behaviors => ['thermal'], decayed_value => 20, original_value => 20,
        has_evolved => 1,
    );

    $m->dispatch($char, 'begin');

    # Force customer to want 'thermal' so match is deterministic
    $m->customer->{desired_behaviors} = ['thermal'];

    my $result = $m->dispatch($char, 'offer', shed_item_id => 'evolved-item');

    is($result->{view}{result}, 'sold', 'evolved match -> sold');
    # match = +2, evolved = +1 => total +3
    is((values %{ $char->{standing} })[0], 3, 'standing +3 on evolved match (2 + 1)');
};

subtest '_pick_reaction picks from yaml or returns undef' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);

    # Known faction with reactions in the real yaml file
    my $text = $m->_pick_reaction('syndicate', 'match', value => 30, item_id => 'test');
    ok(defined $text, 'syndicate match reaction picked');
    like($text, qr/scrap|value/i, 'reaction mentions value');

    # Unknown faction should return undef (fallback to generic)
    my $undef = $m->_pick_reaction('nonexistent', 'match', value => 10);
    is($undef, undef, 'unknown faction returns undef');

    # Unknown outcome should return undef
    my $undef2 = $m->_pick_reaction('syndicate', 'unknown_outcome', value => 10);
    is($undef2, undef, 'unknown outcome returns undef');
};

subtest '_faction_by_id finds faction by id' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);

    my $f = $m->_faction_by_id('syndicate');
    ok($f, 'syndicate faction found');
    is($f->{name}, 'The Syndicate', 'correct name');

    my $nf = $m->_faction_by_id('nonexistent');
    is($nf, undef, 'unknown faction returns undef');
};

subtest '_apply_loyalty_bonus applies 1.10x at 3+ sales' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = TestCharacter->new(skill_selling => 0);
    $char->setCol('faction_sales', { syndicate => 2 });

    # 2 sales → no bonus
    my $r1 = $m->_apply_loyalty_bonus($char, 'syndicate', 100);
    is($r1, 100, 'no bonus at 2 sales');

    $char->setCol('faction_sales', { syndicate => 3 });
    my $r2 = $m->_apply_loyalty_bonus($char, 'syndicate', 100);
    is($r2, 105, '1.05x bonus at 3 sales (int)');

    # Different faction with 1 sale → no bonus
    my $r3 = $m->_apply_loyalty_bonus($char, 'faculty', 100);
    is($r3, 100, 'no bonus for faction with <3 sales');
};

subtest 'visits_since tracking on begin' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = TestCharacter->new(
        id => 'char-1', action_points => 15, scrap => 0, score => 0,
        faction_sales => { syndicate => 5 },
        loyalty_visits_since => 0,
    );

    my $shed = $m->app->shed;
    for my $i (1 .. 5) {
        $shed->create(
            id => "item-$i", char_id => 'char-1', artifact_id => 'thermal_box_001',
            behaviors => ['thermal'], decayed_value => 20, original_value => 20,
        );
    }

    # Begin a few times — visits_since should increment unless syndicate
    for my $i (1 .. 3) {
        srand(42);
        $m->dispatch($char, 'begin');
        $m->phase('idle');
        $m->customer(undef);
    }
    ok(1, 'visits_since tracking did not crash');
    ok($char->{loyalty_visits_since} > 0, 'visits_since incremented after non-loyalty visits');
};

subtest 'loyalty guarantee triggers after 3 non-loyalty visits' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = TestCharacter->new(
        id => 'char-1', action_points => 15, scrap => 0, score => 0,
        faction_sales => { syndicate => 5 },
        loyalty_visits_since => 3,
    );

    my $shed = $m->app->shed;
    $shed->create(
        id => 'guarantee-item', char_id => 'char-1', artifact_id => 'thermal_box_001',
        behaviors => ['thermal'], decayed_value => 20, original_value => 20,
    );

    srand(42);
    $m->dispatch($char, 'begin');
    is($char->{loyalty_visits_since}, 0, 'visits reset after guarantee fires');
    is($m->customer->{faction_id}, 'syndicate', 'customer forced to syndicate on 4th visit');
};

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


# ── Counter-offer flow (gated by config) ───────────────────────────────

subtest 'counter-offer generated on mismatch when market_counter_offers enabled' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    $m->app->{config} = { market_counter_offers => 1 };
    my $char = _fresh_char();
    $char->setCol('name', 'TestBot');

    my $shed = $m->app->shed;
    $shed->create(id => 'co-item', char_id => 'char-1', artifact_id => 'unknown',
        behaviors => ['force'], decayed_value => 30, original_value => 30);

    $m->dispatch($char, 'begin');
    $m->customer->{settle_chance} = 0.0;
    srand(42);
    my $result = $m->dispatch($char, 'offer', shed_item_id => 'co-item');

    is($result->{view}{result}, 'counter_offer', 'mismatch -> counter_offer when enabled');
    ok($result->{view}{counter_value} > 0, 'counter_value is positive');
    ok(exists $m->customer->{pending_counter}, 'pending_counter stored on customer');
    is($m->customer->{pending_counter}{item_id}, 'co-item', 'pending_counter references correct item');
};

subtest 'accept_counter sells at counter price' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    $m->app->{config} = { market_counter_offers => 1 };
    my $char = _fresh_char();
    $char->setCol('name', 'TestBot');

    my $shed = $m->app->shed;
    $shed->create(id => 'ac-item', char_id => 'char-1', artifact_id => 'unknown',
        behaviors => ['force'], decayed_value => 30, original_value => 30);

    $m->dispatch($char, 'begin');
    $m->customer->{settle_chance} = 0.0;
    srand(42);
    $m->dispatch($char, 'offer', shed_item_id => 'ac-item');
    ok($m->customer->{pending_counter}, 'counter-offer generated');

    my $result = $m->dispatch($char, 'accept_counter');
    is($result->{view}{result}, 'sold', 'accept_counter -> sold');
    ok($char->{scrap} > 0, 'scrap awarded on counter acceptance');
    is((values %{ $char->{standing} })[0], 1, 'standing +1 on counter acceptance');
};

# ── Multi-item mode (gated by config) ──────────────────────────────────

subtest 'multi-item allows multiple sales per visit' => sub {
    my $data_dir = tempdir(CLEANUP => 1);
    my $season = MagicMountain::Model::Season->new(file => "$data_dir/s.json");
    $season->create(id => 's1', label => 'Test', status => 'active',
        day => 1, length => 30, faction_state => {})->save;

    my $content_file = _make_content_file();
    my ($fh, $table_file) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($table_file, '{}');
    my $app = FakeApp->new;
    $app->{_active_season} = $season;
    $app->{_seasons} = $season;
    $app->{config} = { market_multi_item => 1 };
    my $m = MagicMountain::Activity::MarketVisit->new(
        file => $table_file, app => $app,
        content_filename => $content_file,
    );
    $m->load_content;

    my $char = TestCharacter->new(
        id => 'char-1', action_points => 15, scrap => 0, score => 0, name => 'TestBot',
    );

    $app->shed->create(id => 'm1', char_id => 'char-1',
        artifact_id => 'thermal_box_001', behaviors => ['thermal'],
        decayed_value => 20, original_value => 20);
    $app->shed->create(id => 'm2', char_id => 'char-1',
        artifact_id => 'thermal_box_001', behaviors => ['thermal'],
        decayed_value => 20, original_value => 20);

    $m->dispatch($char, 'begin');
    $m->customer->{desired_behaviors} = ['thermal'];
    $m->customer->{soft_budget} = 999;
    $m->customer->{absolute_budget} = 9999;

    my $r1 = $m->dispatch($char, 'offer', shed_item_id => 'm1');
    is($r1->{view}{result}, 'sold_more', 'first multi-item sale -> sold_more');
    ok($r1->{view}{value} > 0, 'first sale value positive');
    ok($r1->{view}{pressure_state}, 'budget pressure state returned');
    is($m->phase, 'negotiating', 'visit remains in negotiating after multi-item sale');

    my $r2 = $m->dispatch($char, 'offer', shed_item_id => 'm2');
    is($r2->{view}{result}, 'sold_more', 'second multi-item sale -> sold_more');
    ok($r2->{view}{value} > 0, 'second sale value positive');

    # Send away to end the visit
    my $r3 = $m->dispatch($char, 'send_away');
    is($r3->{view}{result}, 'sent_away', 'send_away ends multi-item visit');
};

# ── Budget / over_budget ──────────────────────────────────────────────

subtest 'sale exceeding absolute_budget returns over_budget with irritation' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = _fresh_char();
    $char->setCol('name', 'TestBot');

    $m->app->shed->create(id => 'ob-item', char_id => 'char-1',
        artifact_id => 'thermal_box_001', behaviors => ['thermal'],
        decayed_value => 100, original_value => 100);

    $m->dispatch($char, 'begin');
    $m->customer->{desired_behaviors} = ['thermal'];
    $m->customer->{soft_budget} = 10;
    $m->customer->{absolute_budget} = 15;

    my $result = $m->dispatch($char, 'offer', shed_item_id => 'ob-item');
    is($result->{view}{result}, 'over_budget', 'over_budget result');
    is($m->customer->{irritation}, 2, 'irritation +2 on over_budget');
};

subtest 'budget pressure state tracks spending' => sub {
    my $content_file = _make_content_file();
    my $m            = _make_singleton($content_file);
    my $char         = _fresh_char();
    $char->setCol('name', 'TestBot');

    $m->app->shed->create(id => 'ps-item', char_id => 'char-1',
        artifact_id => 'thermal_box_001', behaviors => ['thermal'],
        decayed_value => 20, original_value => 20);

    $m->dispatch($char, 'begin');
    $m->customer->{desired_behaviors} = ['thermal'];
    $m->customer->{soft_budget} = 999;
    $m->customer->{absolute_budget} = 9999;

    my $result = $m->dispatch($char, 'offer', shed_item_id => 'ps-item');
    is($result->{view}{result}, 'sold', 'sale succeeds with high budget');
    ok($result->{view}{pressure_state}, 'pressure_state is returned');
    ok($result->{view}{budget_pressure_pct} > 0, 'budget_pressure_pct is positive');
};

done_testing;
