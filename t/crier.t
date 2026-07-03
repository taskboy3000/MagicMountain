use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;
use Test::More;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);

use_ok('MagicMountain::Crier');

sub _make_crier {
    my ($content) = @_;
    my $dir = tempdir(CLEANUP => 1);
    my $file = "$dir/crier.yml";
    write_file($file, $content);
    return MagicMountain::Crier->new(content_file => $file);
}

sub _make_season {
    my (%args) = @_;
    return bless {
        day           => $args{day} // 1,
        faction_state => $args{faction_state} // {},
        crier_snapshot => $args{crier_snapshot} // {},
    }, 'FakeSeason';
}

{
    package FakeSeason;
    sub getCol { my ($self, $col) = @_; $self->{$col} }
}

subtest 'season_opening on day 1' => sub {
    my $c = _make_crier(<<'YAML');
crier_messages:
  season_opening:
    - "A new season dawns!"
  generic:
    - "generic"
YAML
    my $msg = $c->generate(_make_season(day => 1));
    is($msg, 'A new season dawns!', 'season_opening on day 1');
};

subtest 'generic fallthrough with no events' => sub {
    my $c = _make_crier(<<'YAML');
crier_messages:
  generic:
    - "quiet day"
YAML
    my $season = _make_season(day => 5, faction_state => { syndicate => { influence => 10, artifacts_received => 2, name => 'Syndicate' } });
    my $msg = $c->generate($season);
    is($msg, 'quiet day', 'generic falls through with no faction events');
};

subtest 'daily_progress by day range' => sub {
    my $c = _make_crier(<<'YAML');
crier_messages:
  daily_progress:
    - day_max: 3
      messages:
        - "early season"
    - day_min: 4
      day_max: 10
      messages:
        - "mid season"
    - day_min: 11
      messages:
        - "late season"
  generic:
    - "generic fallback"
YAML
    is($c->generate(_make_season(day => 2,  faction_state => { s => {influence=>1,artifacts_received=>1,name=>'S'} }, crier_snapshot => { s => {influence=>1,artifacts_received=>1,name=>'S'} })), 'early season', 'day 2 picks early');
    is($c->generate(_make_season(day => 7,  faction_state => { s => {influence=>1,artifacts_received=>1,name=>'S'} }, crier_snapshot => { s => {influence=>1,artifacts_received=>1,name=>'S'} })), 'mid season',  'day 7 picks mid');
    is($c->generate(_make_season(day => 15, faction_state => { s => {influence=>1,artifacts_received=>1,name=>'S'} }, crier_snapshot => { s => {influence=>1,artifacts_received=>1,name=>'S'} })), 'late season', 'day 15 picks late');
};

subtest 'daily_progress lower priority than faction events' => sub {
    my $c = _make_crier(<<'YAML');
crier_messages:
  faction_surge:
    - "SURGE: {faction} gained {influence_gain}!"
  daily_progress:
    - day_max: 100
      messages:
        - "daily message"
  generic:
    - "generic"
YAML
    my $season = _make_season(
        day => 10,
        faction_state => {
            syndicate => { name => 'Syndicate', influence => 50, artifacts_received => 10 },
        },
        crier_snapshot => {
            syndicate => { name => 'Syndicate', influence => 30, artifacts_received => 5 },
        },
    );
    my $msg = $c->generate($season);
    like($msg, qr/SURGE/, 'faction surge overrides daily_progress');
};

# ── Milestone threshold ────────────────────────────────────────────

subtest 'milestone on artifact receipt threshold crossing' => sub {
    my $c = _make_crier(<<'YAML');
crier_messages:
  milestone:
    - "{faction} received {count} artifacts!"
  generic:
    - "generic"
YAML
    my $season = _make_season(
        day => 10,
        faction_state => {
            syndicate => { name => 'Syndicate', influence => 50, artifacts_received => 10 },
        },
        crier_snapshot => {
            syndicate => { name => 'Syndicate', influence => 30, artifacts_received => 9 },
        },
    );
    my $msg = $c->generate($season);
    like($msg, qr/received/, 'milestone fires at 10 threshold');
};

subtest 'milestone at 25 threshold' => sub {
    my $c = _make_crier(<<'YAML');
crier_messages:
  milestone:
    - "{faction} milestone!"
  generic:
    - "generic"
YAML
    my $season = _make_season(
        day => 10,
        faction_state => {
            syndicate => { name => 'Syndicate', influence => 100, artifacts_received => 25 },
        },
        crier_snapshot => {
            syndicate => { name => 'Syndicate', influence => 80, artifacts_received => 24 },
        },
    );
    my $msg = $c->generate($season);
    like($msg, qr/milestone/, 'milestone at 25 threshold');
};

# ── Slump ──────────────────────────────────────────────────────────

subtest 'slump detected when influence unchanged but had prior activity' => sub {
    my $c = _make_crier(<<'YAML');
crier_messages:
  faction_slump:
    - "SLUMP: {faction}"
  generic:
    - "generic"
YAML
    my $season = _make_season(
        day => 10,
        faction_state => {
            syndicate => { name => 'Syndicate', influence => 50, artifacts_received => 5 },
        },
        crier_snapshot => {
            syndicate => { name => 'Syndicate', influence => 50, artifacts_received => 5 },
        },
    );
    my $msg = $c->generate($season);
    like($msg, qr/SLUMP/, 'slump detected when influence unchanged and prev_recv > 0');
};

# ── Leadership change ──────────────────────────────────────────────

subtest 'faction dominance on leadership change' => sub {
    my $c = _make_crier(<<'YAML');
crier_messages:
  faction_dominance:
    - "{faction} takes the lead!"
  generic:
    - "generic"
YAML
    my $season = _make_season(
        day => 10,
        faction_state => {
            syndicate => { name => 'Syndicate', influence => 100, artifacts_received => 10 },
            faculty   => { name => 'Faculty',   influence => 80,  artifacts_received => 5 },
        },
        crier_snapshot => {
            syndicate => { name => 'Syndicate', influence => 40, artifacts_received => 5 },
            faculty   => { name => 'Faculty',   influence => 80,  artifacts_received => 5 },
        },
    );
    my $msg = $c->generate($season);
    like($msg, qr/lead/, 'dominance on leadership change');
};

# ── Interpolation fallback ─────────────────────────────────────────

subtest 'unknown param preserved literally' => sub {
    my $c = _make_crier(<<'YAML');
crier_messages:
  faction_surge:
    - "{faction} gained {unknown_param}!"
  generic:
    - "generic"
YAML
    my $season = _make_season(
        day => 10,
        faction_state => {
            syndicate => { name => 'Syndicate', influence => 50, artifacts_received => 5 },
        },
        crier_snapshot => {
            syndicate => { name => 'Syndicate', influence => 30, artifacts_received => 3 },
        },
    );
    my $msg = $c->generate($season);
    like($msg, qr/{unknown_param}/, 'unknown param preserved as literal');
};

done_testing;
