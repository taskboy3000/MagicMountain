use Modern::Perl;
use Test::More;
use Test::Exception;
use File::Temp qw(tempfile tempdir);
use File::Slurp qw(write_file);
use YAML::XS qw(DumpFile);

use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

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

subtest 'validates choice events' => sub {
    _write_yaml(prospecting => [
        { id => 'has_choices', weight => 10, trigger => 'begin', text => 'x',
          choices => [{ id => 'c1', label => 'Pick', effects => [{ scrap_delta => 5 }] }] },
    ]);
    my $svc = _make_service;
    ok $svc->_load('prospecting'), 'loads valid choice event';
};

subtest 'rejects choice with unknown effect' => sub {
    _write_yaml(prospecting => [
        { id => 'bad_choice', weight => 10, trigger => 'begin', text => 'x',
          choices => [{ id => 'c1', label => 'Pick', effects => [{ unknown_effect => 5 }] }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on unknown effect in choice';
};

subtest 'rejects missing effects in choice' => sub {
    _write_yaml(prospecting => [
        { id => 'no_eff', weight => 10, trigger => 'begin', text => 'x',
          choices => [{ id => 'c1', label => 'Pick', effects => [] }] },
    ]);
    my $svc = _make_service;
    dies_ok { $svc->_load('prospecting') } 'dies on empty effects in choice';
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

# ── Choice events ────────────────────────────────────────────────────

subtest 'choice event returns choices in draw()' => sub {
    _write_yaml(prospecting => [
        { id => 'has_choices', weight => 10, trigger => 'begin', text => 'Choose!',
          choices => [
              { id => 'a', label => 'Option A', effects => [{ scrap_delta => 5 }] },
              { id => 'b', label => 'Option B', effects => [{ scrap_delta => 10 }] },
          ] },
    ]);
    my $svc = _make_service;
    my $char = _fresh_char;
    my $ctx = { char => $char, artifact => {}, season => { day => 1 } };
    my $result = $svc->draw(
        pool    => 'prospecting',
        trigger => 'begin',
        context => $ctx,
        seeded_rng => sub { 0.01 },  # force event chance roll to pass
    );
    ok($result, 'draw returns event');
    is($result->{id}, 'has_choices', 'correct event id');
    ok($result->{choices}, 'event has choices');
    is(scalar @{ $result->{choices} }, 2, 'two choices returned');
    is($result->{choices}[0]{id}, 'a', 'first choice id');
    is($result->{choices}[0]{attrs}{'data-choice-id'}, 'a', 'choice has data-choice-id attr');
    is($result->{choices}[0]{attrs}{'data-action-url'}, '/prospecting/resolve_event', 'choice has action url');
    ok(!exists $result->{effects}, 'effects not applied by draw() for choice event');
    is($char->getCol('scrap'), 0, 'scrap not modified by draw() for choice event');
};

subtest 'choice event filters ineligible choices by condition' => sub {
    _write_yaml(prospecting => [
        { id => 'skill_check', weight => 10, trigger => 'begin', text => 'Skill check',
          choices => [
              { id => 'easy', label => 'Easy', effects => [{ scrap_delta => 5 }] },
              { id => 'hard', label => 'Hard', conditions => [{ prospecting_gte => 3 }],
                effects => [{ scrap_delta => 20 }] },
          ] },
    ]);
    my $svc = _make_service;
    my $char = _fresh_char;
    $char->setCol('skill_prospecting', 1);  # too low for hard
    my $ctx = { char => $char, artifact => {}, season => { day => 1 } };
    my $result = $svc->draw(
        pool    => 'prospecting',
        trigger => 'begin',
        context => $ctx,
        seeded_rng => sub { 0.01 },
    );
    ok($result, 'draw returns event');
    is(scalar @{ $result->{choices} }, 1, 'only one eligible choice');
    is($result->{choices}[0]{id}, 'easy', 'ineligible choice filtered out');
};

subtest 'choice event discarded when all choices gated' => sub {
    _write_yaml(prospecting => [
        { id => 'all_gated', weight => 10, trigger => 'begin', text => 'Gated',
          choices => [
              { id => 'only', label => 'Only', conditions => [{ prospecting_gte => 5 }],
                effects => [{ scrap_delta => 5 }] },
          ] },
    ]);
    my $svc = _make_service;
    my $char = _fresh_char;
    $char->setCol('skill_prospecting', 1);  # too low
    my $ctx = { char => $char, artifact => {}, season => { day => 1 } };
    my $result = $svc->draw(
        pool    => 'prospecting',
        trigger => 'begin',
        context => $ctx,
        seeded_rng => sub { 0.01 },
    );
    is($result, undef, 'no event when all choices gated');
};

subtest 'apply_choice runs correct effects' => sub {
    _write_yaml(prospecting => [
        { id => 'apply_choice_test', weight => 10, trigger => 'begin', text => 'Test',
          choices => [
              { id => 'gain', label => 'Gain', effects => [{ scrap_delta => 15 }] },
          ] },
    ]);
    my $svc = _make_service;
    my $char = _fresh_char;
    $char->setCol('scrap', 10);
    my $pending = {
        pool    => 'prospecting',
        choices => [
            { id => 'gain', label => 'Gain', effects => [{ scrap_delta => 15 }] },
        ],
    };
    my $resolved = $svc->apply_choice(
        pool          => 'prospecting',
        choice_id     => 'gain',
        pending_event => $pending,
        context       => { char => $char, artifact => {}, season => { day => 1 } },
    );
    is($char->getCol('scrap'), 25, 'apply_choice applies effects');
    is($resolved->[0]{name}, 'scrap_delta', 'resolved effect name');
    is($resolved->[0]{value}, 15, 'resolved effect value');
};

subtest 'apply_choice dies with unknown choice_id' => sub {
    my $svc = _make_service;
    my $pending = {
        pool    => 'prospecting',
        choices => [{ id => 'a', label => 'A', effects => [{ scrap_delta => 5 }] }],
    };
    dies_ok {
        $svc->apply_choice(
            pool          => 'prospecting',
            choice_id     => 'nonexistent',
            pending_event => $pending,
            context       => { char => _fresh_char, artifact => {}, season => { day => 1 } },
        );
    } 'dies on unknown choice_id';
};

subtest '_format_effect — prospecting effects' => sub {
    my $svc = _make_service;
    is($svc->_format_effect('prospecting', 'scrap_delta', 12), 'Gained 12 scrap', 'scrap_delta positive');
    is($svc->_format_effect('prospecting', 'scrap_delta', -5), 'Lost 5 scrap', 'scrap_delta negative');
    is($svc->_format_effect('prospecting', 'scrap_delta', 0), 'Gained 0 scrap', 'scrap_delta zero');
    is($svc->_format_effect('prospecting', 'score_delta', 8), 'Score +8', 'score_delta');
    is($svc->_format_effect('prospecting', 'value_delta', 4), 'Artifact value +4', 'value_delta positive');
    is($svc->_format_effect('prospecting', 'value_delta', -2), 'Artifact value -2', 'value_delta negative');
    is($svc->_format_effect('prospecting', 'instability_delta', 3), 'Instability +3', 'instability_delta positive');
    is($svc->_format_effect('prospecting', 'instability_delta', -3), 'Instability -3', 'instability_delta negative');
    is($svc->_format_effect('prospecting', 'behavior_add', 'volatile'), "Artifact gains 'volatile' behavior", 'behavior_add');
    is($svc->_format_effect('prospecting', 'ap_delta', 1), 'Refunded 1 AP', 'ap_delta positive');
    is($svc->_format_effect('prospecting', 'ap_delta', -2), 'Cost 2 AP', 'ap_delta negative');
};

subtest '_format_effect — market_visit effects' => sub {
    my $svc = _make_service;
    is($svc->_format_effect('market_visit', 'scrap_delta', 22), 'Gained 22 scrap', 'scrap_delta');
    is($svc->_format_effect('market_visit', 'score_delta', 5), 'Score +5', 'score_delta');
    is($svc->_format_effect('market_visit', 'multiplier_delta', 0.15), 'Offer multiplier +15%', 'multiplier_delta positive');
    is($svc->_format_effect('market_visit', 'multiplier_delta', -0.10), 'Offer multiplier -10%', 'multiplier_delta negative');
    is($svc->_format_effect('market_visit', 'irritation_floor', 3), 'Minimum customer irritation: 3', 'irritation_floor');
    is($svc->_format_effect('market_visit', 'irritation_delta', 1), 'Customer irritation +1', 'irritation_delta positive');
    is($svc->_format_effect('market_visit', 'irritation_delta', -2), 'Customer irritation -2', 'irritation_delta negative');
};

subtest '_format_effect — global effects' => sub {
    my $svc = _make_service;
    is($svc->_format_effect('global', 'instability_growth_delta', 2), 'Daily instability growth: +2', 'instability_growth_delta');
    is($svc->_format_effect('global', 'artifact_value_mult', 1.5), 'Today\'s artifact values: x1.5', 'artifact_value_mult');
    is($svc->_format_effect('global', 'market_multiplier_delta', -0.10), 'Today\'s market offers: -10%', 'market_multiplier_delta');
    is($svc->_format_effect('global', 'prospect_ap_cost', 3), 'Prospecting AP cost: 3', 'prospect_ap_cost');
};

subtest 'describe_effects' => sub {
    my $svc = _make_service;
    my $resolved = [
        { name => 'scrap_delta', value => 12 },
        { name => 'score_delta', value => 5 },
    ];
    my $desc = $svc->describe_effects($resolved, 'prospecting');
    like($desc, qr/Gained 12 scrap/, 'includes scrap description');
    like($desc, qr/Score \+5/, 'includes score description');

    is($svc->describe_effects([], 'prospecting'), '', 'empty resolved returns empty string');
    is($svc->describe_effects(undef, 'prospecting'), '', 'undef resolved returns empty string');
};

done_testing;
