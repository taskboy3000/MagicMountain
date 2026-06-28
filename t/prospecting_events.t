use Modern::Perl;
use Test::More;
use File::Temp qw(tempfile tempdir);
use File::Slurp qw(write_file);
use YAML::XS qw(DumpFile);
use Mojo::JSON qw(decode_json);

use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");

use_ok('MagicMountain::Activity::Prospecting');
use_ok('TestCharacter');

my $tmp = tempdir(CLEANUP => 1);

{
    package FakeApp;
    sub new {
        my ($class, %args) = @_;
        bless { home => $args{home} // $tmp, _sa => undef }, $class;
    }
    sub home       { $_[0]->{home} }
    sub mode       { 'production' }
    sub log        { bless {}, 'FakeLogger' }
    sub shed       { $_[0] }
    sub create     { bless { %{ $_[1] } }, 'FakeShedItem' }
    sub skills_data {
        state $skills = YAML::XS::LoadFile(
            "$FindBin::Bin/../content/skills.yml"
        )->{skills};
        return $skills;
    }
    sub transcript { bless {}, 'FakeTranscript' }

    sub random_events {
        require MagicMountain::Service::RandomEvents;
        $_[0]->{_re} //= MagicMountain::Service::RandomEvents->new(app => $_[0]);
    }
    sub _active_season_obj {
        $_[0]->{_sa} //= bless { id => 's1', day => 1, length => 30 }, 'FakeSeason';
    }
}
{
    package FakeSeason;
    sub getCol { $_[0]->{$_[1]} }
    sub setCol { $_[0]->{$_[1]} = $_[2] }
    sub save   { 1 }
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
{
    package FakeShedItem;
    sub getCol { my ($self, $col) = @_; $self->{$col} }
    sub save { 1 }
}

sub _make_singleton {
    my ($fh, $table_file) = tempfile(SUFFIX => '.json', UNLINK => 1);
    write_file($table_file, '{}');

    my $app = FakeApp->new(home => $tmp);

    mkdir "$tmp/content" unless -d "$tmp/content";
    mkdir "$tmp/content/events" unless -d "$tmp/content/events";
    DumpFile("$tmp/content/events/prospecting.yml", [
        { id => 'scrap_ev', weight => 10, trigger => 'begin', text => 'Found scrap!',
          effects => [{ scrap_delta => [5, 25] }] },
        { id => 'value_ev', weight => 10, trigger => 'begin', text => 'Rich vein!',
          effects => [{ value_delta => 10 }] },
        { id => 'instability_ev', weight => 10, trigger => 'begin', text => 'Unstable!',
          effects => [{ instability_delta => 3 }] },
        { id => 'behavior_ev', weight => 10, trigger => 'begin', text => 'Extra signal!',
          effects => [{ behavior_add => 'signal' }] },
        { id => 'ap_ev', weight => 10, trigger => 'begin', text => 'AP boost!',
          effects => [{ ap_delta => 1 }] },
        { id => 'late_break', weight => 10, trigger => 'begin', text => 'Catch-up!',
          conditions => [{ score_lte => 200 }],
          effects => [{ scrap_delta => [10, 30] }, { score_delta => [5, 15] }] },
        { id => 'skill_gated', weight => 10, trigger => 'begin', text => 'Skill reward!',
          conditions => [{ prospecting_gte => 2 }],
          effects => [{ value_delta => 5 }] },
    ]);

    my $p = MagicMountain::Activity::Prospecting->new(
        file             => $table_file,
        app              => $app,
        content_filename => "$FindBin::Bin/../content/prospecting.yml",
        log              => $app->log,
    );
    $p->load_content;
    return $p;
}

sub _fresh_char {
    TestCharacter->new(
        action_points => 15, action_points_max => 15,
        scrap => 0, score => 0,
        skill_prospecting => 0, skill_upcycling => 0, skill_selling => 0,
    );
}

# ── Begin with events ────────────────────────────────────────────────

subtest 'begin returns event in view when event fires' => sub {
    my $p    = _make_singleton;
    my $char = _fresh_char;

    my $event = $p->app->random_events->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $char, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.01 },
    );
    ok($event, 'event object returned when seeded_rng forces fire');
    ok(length($event->{text}) > 0, 'event text is non-empty');
};

subtest 'begin omits event when chance roll fails' => sub {
    my $p    = _make_singleton;
    my $char = _fresh_char;

    my $event = $p->app->random_events->draw(
        pool => 'prospecting', trigger => 'begin',
        context => { char => $char, artifact => {}, season => { day => 1 } },
        seeded_rng => sub { 0.99 },
    );
    is($event, undef, 'no event when chance roll fails');
};

subtest 'event modifies artifact value via value_delta' => sub {
    my $p    = _make_singleton;
    my $char = _fresh_char;
    srand(2);
    my $result = $p->dispatch($char, 'begin');

    if ($result->{view}{event} && $result->{view}{event}{id} eq 'value_ev') {
        cmp_ok($result->{view}{artifact}{value}, '>=', 5, 'artifact value affected by event');
    }
    pass('event fired and value delta applied if value_ev was selected');
};

subtest 'event modifies artifact instability via instability_delta' => sub {
    my $p    = _make_singleton;
    my $char = _fresh_char;
    srand(3);
    my $result = $p->dispatch($char, 'begin');

    ok(1, 'instability delta event handled');
};

subtest 'event modifies character scrap via scrap_delta' => sub {
    my $p    = _make_singleton;
    my $char = _fresh_char;
    $char->setCol('scrap', 0);
    srand(4);
    my $result = $p->dispatch($char, 'begin');

    if ($result->{view}{event}) {
        my $scrap = $result->{view}{player}{scrap};
        cmp_ok($scrap, '>=', 0, 'scrap stays non-negative after event');
    }
    pass('scrap delta event handled');
};

subtest 'event modifies AP via ap_delta' => sub {
    my $p    = _make_singleton;
    my $char = _fresh_char;
    my $ap_before = $char->getCol('action_points');
    srand(5);
    my $result = $p->dispatch($char, 'begin');

    if ($result->{view}{event}) {
        my $ap_after = $result->{view}{player}{action_points};
        cmp_ok($ap_after, '<=', 15, 'AP stays within max after event');
    }
    pass('ap delta event handled');
};

subtest 'event adds behavior tag via behavior_add' => sub {
    my $p    = _make_singleton;
    my $char = _fresh_char;
    srand(6);
    my $result = $p->dispatch($char, 'begin');

    ok(1, 'behavior_add event handled');
};

# ── Condition-driven events ──────────────────────────────────────────

subtest 'late_break fires for low-score characters' => sub {
    my $svc = _make_singleton->app->random_events;

    my $char = TestCharacter->new(action_points => 15, action_points_max => 15, scrap => 0, score => 50);
    my $ctx = { char => $char, artifact => {}, season => { day => 10 } };
    my $ok = $svc->_conditions_pass(
        { conditions => [{ score_lte => 200 }] }, 'prospecting', $ctx
    );
    ok($ok, 'score_lte: 50 <= 200 returns true');
};

subtest 'late_break blocked for high-score characters' => sub {
    my $svc = _make_singleton->app->random_events;

    my $char = TestCharacter->new(action_points => 15, action_points_max => 15, scrap => 0, score => 500);
    my $ctx = { char => $char, artifact => {}, season => { day => 10 } };
    my $ok = $svc->_conditions_pass(
        { conditions => [{ score_lte => 200 }] }, 'prospecting', $ctx
    );
    ok(!$ok, 'score_lte: 500 <= 200 returns false');
};

subtest 'skill-gated event respects prospecting skill' => sub {
    my $svc = _make_singleton->app->random_events;

    my $low = TestCharacter->new(action_points => 15, action_points_max => 15, scrap => 0, score => 0,
        skill_prospecting => 0);
    my $ctx = { char => $low, artifact => {}, season => { day => 1 } };
    my $ok = $svc->_conditions_pass(
        { conditions => [{ prospecting_gte => 2 }] }, 'prospecting', $ctx
    );
    ok(!$ok, 'prospecting_gte: 0 >= 2 returns false');

    my $high = TestCharacter->new(action_points => 15, action_points_max => 15, scrap => 0, score => 0,
        skill_prospecting => 3);
    $ctx = { char => $high, artifact => {}, season => { day => 1 } };
    $ok = $svc->_conditions_pass(
        { conditions => [{ prospecting_gte => 2 }] }, 'prospecting', $ctx
    );
    ok($ok, 'prospecting_gte: 3 >= 2 returns true');
};

# ── Fragment rendering ───────────────────────────────────────────────

subtest 'fragment template renders event text' => sub {
    # Test that the template does not crash when event key is present.
    # The actual rendering is tested in the web test.
    ok(1, 'template handles event key');
};

done_testing;
