use Modern::Perl;

use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");

use Test::More;
use File::Temp qw(tempfile tempdir);
use File::Slurp qw(write_file);
use Mojo::JSON qw(encode_json decode_json);

use_ok('MagicMountain::Activity::Prospecting');
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
}
{
    package FakeShedItem;
    sub getCol { my ($self, $col) = @_; $self->{$col} }
    sub save { 1 }
}
{
    package FakeLogger;
    sub debug { }
    sub info  { }
    sub warn  { }
    sub error { }
    sub fatal { }
}

sub _make_content_file {
    my ($fh, $file) = tempfile(SUFFIX => '.yml', UNLINK => 1);

    write_file($file, <<'YAML');
- id: thermal_box_001
  behaviors: [thermal]
  weight: 10
  base_value: 5
  starting_instability: 0
  max_instability: 14
  instability_growth_min: 1
  instability_growth_max: 2
  base_gain_min: 3
  base_gain_max: 5
  can_evolve: true
  evolution_threshold: 0.30
  evolution_chance: 1.0
  state_thresholds:
    stable: 0.35
    strained: 0.70
  intro: A warm box.
  signals:
    stable:
      - Stable signal A.
      - Stable signal B.
    strained:
      - Strained signal.
    unstable:
      - Unstable signal.
  collapse:
    - It breaks apart.

- id: crystal_chime_001
  behaviors: [signal, field]
  weight: 5
  base_value: 8
  starting_instability: 0
  max_instability: 10
  instability_growth_min: 1
  instability_growth_max: 3
  base_gain_min: 4
  base_gain_max: 8
  can_evolve: true
  evolution_threshold: 0.40
  evolution_chance: 1.0
  evolution_instability_spike: 3
  breakthrough_multiplier_min: 2.0
  breakthrough_multiplier_max: 2.0
  state_thresholds:
    stable: 0.30
    strained: 0.60
  intro: A chime crystal.
  signals:
    stable:
      - Chime stable.
    strained:
      - Chime strained.
    unstable:
      - Chime unstable.
  collapse:
    - Crystal shatters.
YAML

    return $file;
}

sub _make_singleton {
    my $content_file = shift;
    my ($fh, $table_file) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($table_file, '{}');

    my $p = MagicMountain::Activity::Prospecting->new(
        file             => $table_file,
        app              => FakeApp->new,
        content_filename => $content_file,
    );
    $p->load_content;
    return $p;
}

sub _fresh_char {
    TestCharacter->new(
        action_points => 15,
        scrap         => 0,
        score         => 0,
    );
}

# ── Content Loading ──────────────────────────────────────────────────

subtest 'content loading from YAML' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);

    my $specs = $p->content_data;
    is(scalar @$specs, 2, 'loaded 2 artifact specs');

    my %by_id = map { $_->{id} => $_ } @$specs;

    my $thermal = $by_id{thermal_box_001};
    ok($thermal, 'thermal_box_001 loaded');
    is($thermal->{intro}, 'A warm box.', 'intro loaded');
    ok(exists $thermal->{signals}{stable}, 'signals hash loaded');
    is(scalar @{ $thermal->{signals}{stable} }, 2, '2 stable signals');
    is(scalar @{ $thermal->{collapse} },        1, '1 collapse text');

    my $crystal = $by_id{crystal_chime_001};
    ok($crystal, 'crystal_chime_001 loaded');
    is($crystal->{intro},     'A chime crystal.', 'crystal intro');
    is($crystal->{can_evolve}, 1,                  'crystal can evolve');
};

subtest 'load_content is idempotent' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);

    my $data1 = $p->content_data;
    $p->load_content;
    my $data2 = $p->content_data;
    is($data1, $data2, 'second load_content call returns same data');
};

# ── Begin ─────────────────────────────────────────────────────────────

subtest 'begin draws artifact and transitions to processing' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);
    my $char         = _fresh_char();

    srand(42);
    my $result = $p->dispatch($char, 'begin');

    is($p->phase, 'processing', 'phase -> processing after begin');

    my $v = $result->{view};
    ok($v->{ok},          'ok is true');
    is($v->{result},      'start', 'result is start');
    ok($v->{artifact}{id},         'artifact has id');
    ok($v->{artifact}{value} > 0,  'artifact has positive value');
    is($v->{artifact}{stage}, 'stable', 'artifact starts stable');
    ok(length $v->{artifact}{signal} > 0, 'signal text present');
    ok(length $v->{artifact}{intro}  > 0, 'intro text present');

    is($char->{action_points}, 13, 'AP deducted (15 → 13)');

    my $artifact = $p->artifact;
    ok($artifact->{instability} == 0, 'instability starts at 0');
    ok($artifact->{push_count} == 0,  'push_count starts at 0');
    ok($artifact->{has_evolved} == 0, 'has_evolved is false');
};

subtest 'begin dies if no turns remaining' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);
    my $char         = TestCharacter->new(action_points => 0, scrap => 0, score => 0);

    eval { $p->dispatch($char, 'begin') };
    like($@, qr/AP exhausted/, 'begin dies on zero AP');
};

subtest 'begin from wrong phase dies' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);
    my $char         = _fresh_char();

    $p->phase('processing');
    eval { $p->dispatch($char, 'begin') };
    like($@, qr/illegal transition/, 'begin from processing dies');
};

# ── Push ──────────────────────────────────────────────────────────────

subtest 'push increases value and instability' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);
    my $char         = _fresh_char();

    $p->dispatch($char, 'begin');
    my $artifact_before = { %{ $p->artifact } };

    srand(123);
    my $result = $p->dispatch($char, 'push');
    my $artifact_after = $p->artifact;

    if ($result->{view}{result} eq 'push') {
        cmp_ok($artifact_after->{value},       '>', $artifact_before->{value},       'value increased');
        cmp_ok($artifact_after->{instability}, '>', $artifact_before->{instability}, 'instability increased');
        cmp_ok($artifact_after->{push_count},  '>', $artifact_before->{push_count},  'push_count incremented');
        is($p->phase, 'processing', 'phase stays processing after normal push');
    } else {
        pass('push resulted in collapse — acceptable outcome');
        is($p->phase, 'idle', 'phase -> idle on collapse');
    }
};

subtest 'push from idle dies' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);
    my $char         = _fresh_char();

    eval { $p->dispatch($char, 'push') };
    like($@, qr/illegal transition/, 'push from idle dies');
};

subtest 'push never exposes internal math in view' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);
    my $char         = _fresh_char();

    $p->dispatch($char, 'begin');

    srand(99);
    my $result = $p->dispatch($char, 'push');
    my $view = $result->{view};

    if ($view->{result} eq 'push') {
        ok(!exists $view->{artifact}{instability},      'instability not in view');
        ok(!exists $view->{artifact}{push_count},       'push_count not in view');
        ok(!exists $view->{artifact}{max_instability},  'max_instability not in view');
        ok(!exists $view->{artifact}{evolution_chance}, 'evolution_chance not in view');
    } else {
        ok(!exists $view->{instability}, 'collapse result hides internal math');
    }
};

# ── Collapse ──────────────────────────────────────────────────────────

subtest 'guaranteed collapse when instability exceeds max' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);
    my $char         = _fresh_char();

    $p->dispatch($char, 'begin');

    my $art = $p->artifact;
    $art->{instability} = $art->{max_instability} + 100;
    $p->artifact($art);

    my $result = $p->dispatch($char, 'push');

    is($result->{view}{result}, 'collapse', 'result is collapse');
    is($result->{view}{reward}, 0,          'reward is 0');
    ok(length($result->{view}{message}) > 0, 'collapse message present');
    is($p->phase,               'idle',     'phase -> idle');
    is($p->artifact,            undef,      'artifact cleared');

    is($char->{scrap}, 0, 'scrap unchanged on collapse');
    is($char->{score}, 0, 'score unchanged on collapse');
};

# ── Breakthrough ──────────────────────────────────────────────────────

subtest 'breakthrough awards value and clears activity' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);
    my $char         = _fresh_char();

    $p->dispatch($char, 'begin');

    my $art = $p->artifact;
    $art->{can_evolve} = 1;
    $art->{has_evolved} = 0;
    $art->{evolution_chance} = 1.0;
    $art->{evolution_threshold} = 0;
    $art->{instability} = 0;
    $art->{instability_growth_min} = 0;
    $art->{instability_growth_max} = 0;
    $art->{max_instability} = 100000;
    $art->{value} = 50;
    $art->{breakthrough_multiplier_min} = 2.0;
    $art->{breakthrough_multiplier_max} = 2.0;
    $p->artifact($art);

    # Collapse has a 5% floor, so seed to avoid that roll.
    # With srand(1), first rand() = 0.0416... < 0.05 → collapse
    # With srand(2), first rand() = 0.7009... >= 0.05 → no collapse
    srand(2);
    my $result = $p->dispatch($char, 'push');

    is($result->{view}{result}, 'breakthrough', 'result is breakthrough');
    ok($result->{view}{reward} > 0,             'reward is positive');
    ok($char->{scrap}           > 0,            'scrap awarded');
    ok($char->{score}           > 0,            'score awarded');
    is($p->phase, 'idle',                        'phase -> idle');
    is($p->artifact, undef,                      'artifact cleared');
};

# ── Stop ──────────────────────────────────────────────────────────────

subtest 'stop from idle dies' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);
    my $char         = _fresh_char();

    eval { $p->dispatch($char, 'stop') };
    like($@, qr/illegal transition/, 'stop from idle dies');
};

# ── Persistence: save/load via Model ──────────────────────────────────

subtest 'save and load activity from JSON via Model' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);
    my $char         = _fresh_char();

    my $activity = $p->create(char_id => 'char-abc');
    is($activity->getCol('type'), 'prospecting', 'type defaults to prospecting');

    $activity->dispatch($char, 'begin');
    ok($activity->getCol('id'), 'begin handler saves and assigns id');
    $activity->save;
    ok($activity->getCol('id'), 'save assigns id');

    my $loaded = $p->get($activity->getCol('id'));
    ok($loaded,                          'get loads from table');
    is($loaded->phase,     'processing', 'phase preserved after load');
    is($loaded->getCol('char_id'), 'char-abc', 'char_id preserved');
    ok($loaded->artifact,                 'artifact preserved');

    my $art = $loaded->artifact;
    ok($art->{id},    'artifact id preserved');
    ok($art->{value} > 0, 'artifact value preserved');

    # Ephemeral attributes should be propagated
    ok($loaded->content_data, 'content_data propagated to loaded instance');
};

subtest 'create returns unsaved instance' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);

    my $a = $p->create(char_id => 'char-x');
    is($a->phase,              'idle',         'default phase');
    is($a->getCol('type'),     'prospecting',  'type defaults to prospecting');
    is($a->getCol('char_id'),  'char-x',       'char_id set');
    is($a->getCol('id'),       undef,           'no id yet — unsaved');

    ok($a->content_data, 'content_data propagated to new instance');
};

subtest 'stop deletes activity row and creates shed item' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);
    my $char         = _fresh_char();

    $p->dispatch($char, 'begin');
    $p->setCol('char_id', 'char-123');
    $p->save;
    my $id = $p->getCol('id');

    $p->dispatch($char, 'stop');

    ok($p->app->{_shed_items} && @{ $p->app->{_shed_items} } == 1, 'shed item created');

    my $reloaded = $p->get($id);
    is($reloaded, undef, 'activity row deleted from table');
};

# ── Full lifecycle ───────────────────────────────────────────────────

subtest 'full begin -> push×N -> stop lifecycle' => sub {
    my $content_file = _make_content_file();
    my $p            = _make_singleton($content_file);
    my $char         = TestCharacter->new(action_points => 3, scrap => 0, score => 0);

    srand(777);
    $p->dispatch($char, 'begin');
    is($char->{action_points}, 1, 'AP deducted (3 → 1)');

    for (1 .. 2) {
        my $r = $p->dispatch($char, 'push');
        last if $r->{view}{result} ne 'push';
        is($p->phase, 'processing', "push $_ still processing");
    }

    SKIP: {
        skip 'artifact collapsed during pushes', 1 if $p->phase ne 'processing';
        my $r = $p->dispatch($char, 'stop');
        is($r->{view}{result}, 'stopped', 'stop -> stopped');
    }
};

done_testing;
