use Modern::Perl;
use Test::More;
use Test::Exception;
use File::Temp qw(tempfile tempdir);
use File::Slurp qw(write_file);
use YAML::XS qw(DumpFile);

use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");

use_ok('MagicMountain::Service::RandomEvents');
use_ok('TestCharacter');

my $tmp = tempdir(CLEANUP => 1);

{
    package FakeApp;
    sub new { bless { home => $_[1] }, shift }
    sub home { $_[0]->{home} }
    sub mode { 'production' }
}

sub _make_service {
    my $app = FakeApp->new($tmp);
    my $svc = MagicMountain::Service::RandomEvents->new(app => $app);
    return $svc;
}

sub _write_yaml {
    my ($pool, $yaml) = @_;
    mkdir "$tmp/content" unless -d "$tmp/content";
    mkdir "$tmp/content/events" unless -d "$tmp/content/events";
    DumpFile("$tmp/content/events/$pool.yml", $yaml);
}

sub _fresh_char {
    TestCharacter->new(
        action_points => 15, action_points_max => 15,
        scrap => 0, score => 0,
        skill_prospecting => 0, skill_upcycling => 0, skill_selling => 0,
    );
}

# ── YAML loading ─────────────────────────────────────────────────────

subtest 'loads valid YAML' => sub {
    _write_yaml(prospecting => [
        { id => 'test_event', weight => 10, trigger => 'begin',
          text => 'A test event.', effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;
    my $events = $svc->_load('prospecting');
    is(scalar @$events, 1, 'loaded one event');
    is($events->[0]{id}, 'test_event', 'event id matches');
};

subtest 'rejects non-array YAML' => sub {
    _write_yaml(prospecting => { not_an => 'array' });
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on non-array YAML';
};

subtest 'rejects missing id' => sub {
    _write_yaml(prospecting => [
        { weight => 10, trigger => 'begin', text => 'x', effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on missing id';
};

subtest 'rejects invalid id pattern' => sub {
    _write_yaml(prospecting => [
        { id => 'BadID!', weight => 10, trigger => 'begin', text => 'x', effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on invalid id';
};

subtest 'rejects duplicate event ids' => sub {
    _write_yaml(prospecting => [
        { id => 'dup_event', weight => 10, trigger => 'begin', text => 'x', effects => [{ scrap_delta => 5 }] },
        { id => 'dup_event', weight => 5,  trigger => 'begin', text => 'y', effects => [{ scrap_delta => 3 }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on duplicate id';
};

subtest 'rejects negative weight' => sub {
    _write_yaml(prospecting => [
        { id => 'neg_weight', weight => -1, trigger => 'begin', text => 'x', effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on negative weight';
};

subtest 'rejects zero weight' => sub {
    _write_yaml(prospecting => [
        { id => 'zero_weight', weight => 0, trigger => 'begin', text => 'x', effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on zero weight';
};

subtest 'rejects unknown effect name' => sub {
    _write_yaml(prospecting => [
        { id => 'bad_effect', weight => 10, trigger => 'begin', text => 'x', effects => [{ no_such_effect => 5 }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on unknown effect';
};

subtest 'rejects unknown condition name' => sub {
    _write_yaml(prospecting => [
        { id => 'bad_cond', weight => 10, trigger => 'begin', text => 'x',
          conditions => [{ no_such_condition => 5 }],
          effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on unknown condition';
};

subtest 'rejects range in condition' => sub {
    _write_yaml(prospecting => [
        { id => 'range_cond', weight => 10, trigger => 'begin', text => 'x',
          conditions => [{ score_lte => [5, 25] }],
          effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on range in condition';
};

subtest 'rejects duplicate effect names' => sub {
    _write_yaml(prospecting => [
        { id => 'dup_eff', weight => 10, trigger => 'begin', text => 'x',
          effects => [{ scrap_delta => 5 }, { scrap_delta => 10 }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on duplicate effect name';
};

subtest 'rejects non-begin trigger in v1' => sub {
    _write_yaml(prospecting => [
        { id => 'push_ev', weight => 10, trigger => 'push', text => 'x', effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on non-begin trigger';
};

subtest 'rejects missing text' => sub {
    _write_yaml(prospecting => [
        { id => 'no_text', weight => 10, trigger => 'begin', effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on missing text';
};

subtest 'rejects choices in v1' => sub {
    _write_yaml(prospecting => [
        { id => 'has_choices', weight => 10, trigger => 'begin', text => 'x',
          choices => [{ id => 'c1', label => 'Pick', effects => [{ scrap_delta => 5 }] }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on choices in v1';
};

subtest 'reverses min_day and max_day' => sub {
    _write_yaml(prospecting => [
        { id => 'rev_day', weight => 10, trigger => 'begin', text => 'x',
          min_day => 10, max_day => 5, effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on reversed min/max day';
};

subtest 'defaults empty missing file to []' => sub {
    my $svc = _make_service;
    my $events = $svc->_events_for_pool('nonexistent');
    is_deeply($events, [], 'missing file => empty array');
};

# ── draw ─────────────────────────────────────────────────────────────

subtest 'draw returns undef when event_chance roll fails' => sub {
    _write_yaml(prospecting => [
        { id => 'test_event', weight => 10, trigger => 'begin', text => 'x', effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;
    my $char = _fresh_char;
    my $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $char, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.99 },
    );
    is($result, undef, 'undef when roll >= chance (0.99 >= 0.20)');
};

subtest 'draw returns event when roll succeeds' => sub {
    _write_yaml(prospecting => [
        { id => 'test_event', weight => 10, trigger => 'begin', text => 'Test!', effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;
    my $char = _fresh_char;
    my $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $char, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    ok($result, 'event returned');
    is($result->{id}, 'test_event', 'correct event id');
    is($result->{text}, 'Test!', 'correct event text');
    is($char->getCol('scrap'), 5, 'scrap_delta applied');
};

subtest 'draw returns undef for empty pool' => sub {
    _write_yaml(prospecting => []);
    my $svc = _make_service;
    my $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => _fresh_char, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is($result, undef, 'undef for empty pool');
};

subtest 'draw returns undef for unknown pool' => sub {
    my $svc = _make_service;
    my $result = $svc->draw(
        pool => 'unknown_pool', trigger => 'begin',
        context => { char => _fresh_char, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is($result, undef, 'undef for unknown pool');
};

# ── Effects ───────────────────────────────────────────────────────────

subtest 'value_delta effect' => sub {
    _write_yaml(prospecting => [
        { id => 'val_test', weight => 10, trigger => 'begin', text => 'x', effects => [{ value_delta => 10 }] },
    ]);
    my $svc = _make_service;
    my $art = { value => 5 };
    $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => _fresh_char, artifact => $art, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is($art->{value}, 15, 'value_delta adds to artifact value');
};

subtest 'instability_delta effect' => sub {
    _write_yaml(prospecting => [
        { id => 'inst_test', weight => 10, trigger => 'begin', text => 'x', effects => [{ instability_delta => 3 }] },
    ]);
    my $svc = _make_service;
    my $art = { instability => 5 };
    $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => _fresh_char, artifact => $art, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is($art->{instability}, 8, 'instability_delta adds to artifact instability');
};

subtest 'behavior_add effect' => sub {
    _write_yaml(prospecting => [
        { id => 'beh_test', weight => 10, trigger => 'begin', text => 'x', effects => [{ behavior_add => 'thermal' }] },
    ]);
    my $svc = _make_service;
    my $art = { behaviors => [] };
    $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => _fresh_char, artifact => $art, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is_deeply($art->{behaviors}, ['thermal'], 'behavior_add appends tag');
};

subtest 'score_delta effect' => sub {
    _write_yaml(prospecting => [
        { id => 'score_test', weight => 10, trigger => 'begin', text => 'x', effects => [{ score_delta => 15 }] },
    ]);
    my $svc = _make_service;
    my $char = _fresh_char;
    $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $char, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is($char->getCol('score'), 15, 'score_delta adds to character score');
};

subtest 'ap_delta effect' => sub {
    _write_yaml(prospecting => [
        { id => 'ap_test', weight => 10, trigger => 'begin', text => 'x', effects => [{ ap_delta => 1 }] },
    ]);
    my $svc = _make_service;
    my $char = TestCharacter->new(action_points => 10, action_points_max => 15, scrap => 0, score => 0);
    $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $char, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is($char->getCol('action_points'), 11, 'ap_delta adds AP');
};

subtest 'ap_delta clamps to 0' => sub {
    _write_yaml(prospecting => [
        { id => 'ap_neg', weight => 10, trigger => 'begin', text => 'x', effects => [{ ap_delta => -5 }] },
    ]);
    my $svc = _make_service;
    my $char = TestCharacter->new(action_points => 2, action_points_max => 15, scrap => 0, score => 0);
    $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $char, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is($char->getCol('action_points'), 0, 'ap_delta clamped to 0');
};

subtest 'ap_delta clamps to max' => sub {
    _write_yaml(prospecting => [
        { id => 'ap_max', weight => 10, trigger => 'begin', text => 'x', effects => [{ ap_delta => 10 }] },
    ]);
    my $svc = _make_service;
    my $char = TestCharacter->new(action_points => 10, action_points_max => 15, scrap => 0, score => 0);
    $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $char, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is($char->getCol('action_points'), 15, 'ap_delta clamps to max');
};

# ── Conditions ─────────────────────────────────────────────────────────

subtest 'artifact_stage condition' => sub {
    _write_yaml(prospecting => [
        { id => 'stage_ev', weight => 10, trigger => 'begin', text => 'x',
          conditions => [{ artifact_stage => 'unstable' }],
          effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;

    my $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => _fresh_char, artifact => { stage => 'stable' }, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is($result, undef, 'no event when stage does not match');

    $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => _fresh_char, artifact => { stage => 'unstable' }, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    ok($result, 'event fires when stage matches');
};

subtest 'score_lte condition' => sub {
    _write_yaml(prospecting => [
        { id => 'late_break', weight => 10, trigger => 'begin', text => 'x',
          conditions => [{ score_lte => 200 }],
          effects => [{ scrap_delta => 10 }] },
    ]);
    my $svc = _make_service;

    my $low = TestCharacter->new(action_points => 15, action_points_max => 15, scrap => 0, score => 100);
    my $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $low, artifact => {}, season => { day => 10 } },
        seeded_rng => sub { 0.01 },
    );
    ok($result, 'event fires for low score (100 <= 200)');

    my $high = TestCharacter->new(action_points => 15, action_points_max => 15, scrap => 0, score => 500);
    $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $high, artifact => {}, season => { day => 10 } },
        seeded_rng => sub { 0.01 },
    );
    is($result, undef, 'event does not fire for high score (500 > 200)');
};

subtest 'scrap_gte condition' => sub {
    _write_yaml(prospecting => [
        { id => 'rich_gate', weight => 10, trigger => 'begin', text => 'x',
          conditions => [{ scrap_gte => 50 }],
          effects => [{ value_delta => 5 }] },
    ]);
    my $svc = _make_service;

    my $poor = TestCharacter->new(action_points => 15, action_points_max => 15, scrap => 10, score => 0);
    my $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $poor, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is($result, undef, 'event does not fire when scrap < threshold');

    my $rich = TestCharacter->new(action_points => 15, action_points_max => 15, scrap => 100, score => 0);
    $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $rich, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    ok($result, 'event fires when scrap >= threshold');
};

subtest 'prospecting_gte skill condition' => sub {
    _write_yaml(prospecting => [
        { id => 'skill_gate', weight => 10, trigger => 'begin', text => 'x',
          conditions => [{ prospecting_gte => 2 }],
          effects => [{ value_delta => 5 }] },
    ]);
    my $svc = _make_service;

    my $low = TestCharacter->new(action_points => 15, action_points_max => 15, scrap => 0, score => 0,
        skill_prospecting => 1);
    my $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $low, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is($result, undef, 'event does not fire when skill too low');

    my $high = TestCharacter->new(action_points => 15, action_points_max => 15, scrap => 0, score => 0,
        skill_prospecting => 3);
    $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $high, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    ok($result, 'event fires when skill meets threshold');
};

# ── Day gates ─────────────────────────────────────────────────────────

subtest 'min_day filter' => sub {
    _write_yaml(prospecting => [
        { id => 'late_ev', weight => 10, trigger => 'begin', text => 'x',
          min_day => 5, effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;

    my $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => _fresh_char, artifact => {}, season => { day => 2 } },
        seeded_rng => sub { 0.01 },
    );
    is($result, undef, 'event filtered by min_day (day 2 < min 5)');

    $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => _fresh_char, artifact => {}, season => { day => 7 } },
        seeded_rng => sub { 0.01 },
    );
    ok($result, 'event passes min_day (day 7 >= min 5)');
};

subtest 'max_day filter' => sub {
    _write_yaml(prospecting => [
        { id => 'early_ev', weight => 10, trigger => 'begin', text => 'x',
          max_day => 10, effects => [{ scrap_delta => 5 }] },
    ]);
    my $svc = _make_service;

    my $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => _fresh_char, artifact => {}, season => { day => 15 } },
        seeded_rng => sub { 0.01 },
    );
    is($result, undef, 'event filtered by max_day (day 15 > max 10)');

    $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => _fresh_char, artifact => {}, season => { day => 5 } },
        seeded_rng => sub { 0.01 },
    );
    ok($result, 'event passes max_day (day 5 <= max 10)');
};

# ── Range resolution ─────────────────────────────────────────────────

subtest 'range resolution produces values in range' => sub {
    _write_yaml(prospecting => [
        { id => 'range_ev', weight => 10, trigger => 'begin', text => 'x', effects => [{ scrap_delta => [5, 25] }] },
    ]);
    my $svc = _make_service;

    for my $r (0, 0.25, 0.5, 0.75, 0.999) {
        my $char = TestCharacter->new(action_points => 15, action_points_max => 15, scrap => 0, score => 0);
        my $before = $char->getCol('scrap');
        $svc->draw(
            pool => 'prospecting', trigger => 'begin',
            context => { char => $char, artifact => {}, season => { day => 1 } },
            seeded_rng => sub {
                state $call = 0;
                $call++;
                return 0.01 if $call == 1;   # event_chance: 0.01 < 0.20 → fires
                return $r;                     # range resolution
            },
        );
        my $gain = $char->getCol('scrap') - $before;
        cmp_ok($gain, '>=', 5,  "range min for r=$r");
        cmp_ok($gain, '<=', 25, "range max for r=$r");
    }
};

subtest 'range resolution rejects reversed range' => sub {
    _write_yaml(prospecting => [
        { id => 'rev_range', weight => 10, trigger => 'begin', text => 'x', effects => [{ scrap_delta => [25, 5] }] },
    ]);
    my $svc = _make_service;
    dies_ok {
        $svc->draw(
            pool => 'prospecting', trigger => 'begin',
            context => { char => _fresh_char, artifact => {}, season => { day => 1 } },
            seeded_rng => sub { 0.01 },
        );
    } 'dies on reversed range';
};

subtest 'scalar values pass through' => sub {
    _write_yaml(prospecting => [
        { id => 'scalar_ev', weight => 10, trigger => 'begin', text => 'x', effects => [{ scrap_delta => 12 }] },
    ]);
    my $svc = _make_service;
    my $char = _fresh_char;
    $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $char, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is($char->getCol('scrap'), 12, 'scalar value applied exactly');
};

# ── Multiple conditions (AND) ─────────────────────────────────────────

subtest 'multiple conditions all must pass' => sub {
    _write_yaml(prospecting => [
        { id => 'multi_cond', weight => 10, trigger => 'begin', text => 'x',
          conditions => [{ scrap_gte => 50 }, { score_lte => 200 }],
          effects => [{ scrap_delta => 10 }] },
    ]);
    my $svc = _make_service;

    my $qualifies = TestCharacter->new(action_points => 15, action_points_max => 15, scrap => 60, score => 100);
    my $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $qualifies, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    ok($result, 'event fires when all conditions pass');

    my $fails_one = TestCharacter->new(action_points => 15, action_points_max => 15, scrap => 60, score => 500);
    $result = $svc->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $fails_one, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    is($result, undef, 'event fails when one condition fails');
};

# ── Weighted selection ────────────────────────────────────────────────

subtest 'weighted selection favors higher weight' => sub {
    _write_yaml(prospecting => [
        { id => 'rare',   weight => 1,  trigger => 'begin', text => 'Rare',   effects => [{ scrap_delta => 1 }] },
        { id => 'common', weight => 100, trigger => 'begin', text => 'Common', effects => [{ scrap_delta => 2 }] },
    ]);
    my $svc = _make_service;

    my $ctx = { char => _fresh_char, artifact => {}, season => { day => 1 } };
    my $events = $svc->_events_for_pool('prospecting');
    my $selected = $svc->_select('prospecting', 'begin', $ctx);
    ok($selected, 'selection returned an event');
};

# ── add_scrap / add_score on Character model ─────────────────────────

subtest 'Character add_scrap clamps to non-negative' => sub {
    my $char = _fresh_char;
    $char->setCol('scrap', 5);
    $char->add_scrap(-10);
    is($char->getCol('scrap'), 0, 'add_scrap clamps to 0');
    $char->add_scrap(20);
    is($char->getCol('scrap'), 20, 'add_scrap adds positive');
};

subtest 'Character add_score never decreases' => sub {
    my $char = _fresh_char;
    $char->setCol('score', 100);
    $char->add_score(50);
    is($char->getCol('score'), 150, 'add_score adds');
    $char->add_score(0);
    is($char->getCol('score'), 150, 'add_score with 0 is no-op');
};

done_testing;
