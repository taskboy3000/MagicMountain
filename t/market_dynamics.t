use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::Model::Season;
use MagicMountain::Activity::MarketVisit;

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
        $self->{_dispositions} //= [];
        return $self;
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
}
{
    package FakeShedItem;
    sub new { my $class = shift; bless { @_ }, $class }
    sub getCol { my ($self, $col) = @_; $self->{$col} }
    sub setCol { my ($self, $col, $val) = @_; $self->{$col} = $val }
    sub save { 1 }
    sub delete { 1 }
}
{
    package FakeTranscript;
    sub log_event { 1 }
}

my $data_dir = tempdir(CLEANUP => 1);
my $season_file = "$data_dir/seasons.json";

my $season = MagicMountain::Model::Season->new(file => $season_file);
$season->create(
    id     => 's1', label => 'Test', status => 'active',
    day    => 1, length => 30,
    faction_state => {},
)->save;

my $app = FakeApp->new;
$app->{_seasons} = $season;
$app->{_active_season} = $season;

# Content with per-faction appetite/desperation params
my $content_file = "$data_dir/factions.yml";
write_file($content_file, <<'YAML');
factions:
  - id: syndicate
    name: "The Syndicate"
    interests: [thermal]
    base_multiplier: 1.1
    daily_appetite_base: 2
    desperation_days: 3
YAML

# Override config values for deterministic testing
$app->{config} = {
    market_trait_saturation_rate   => 0.10,
    market_max_saturation_discount => 0.50,
    market_post_appetite_penalty   => 0.50,
    market_desperation_bonus       => 2.00,
};

my $char = bless {
    id            => 'char-1',
    action_points => 15,
    scrap         => 0,
    score         => 0,
}, 'FakeShedItem';

# Helper: create a fresh MarketVisit handler
sub fresh_market {
    my $m = MagicMountain::Activity::MarketVisit->new(
        file             => "$data_dir/activities.json",
        app              => $app,
        content_filename => $content_file,
        log              => $app->log,
    );
    $m->load_content;
    return $m;
}

subtest 'base multiplier when no sales yet' => sub {
    $season->setCol('faction_state', {});
    $season->save;

    my $m = fresh_market();
    $app->shed->create(
        id => 'item-base', char_id => 'char-1',
        artifact_id => 'test', behaviors => ['thermal'],
        decayed_value => 20, original_value => 20,
    );
    $m->dispatch($char, 'begin');
    my $result = $m->dispatch($char, 'offer', shed_item_id => 'item-base');
    my $view = $result->{view};
    is($view->{result}, 'sold', 'first sale succeeds');
    # With no saturation: 20 * 1.1(base) * 1.2(match) = 26.4 → 26
    is($view->{value}, 26, 'first sale at base multiplier');

    $season->load;
    my $fs = $season->getCol('faction_state');
    is($fs->{syndicate}{daily_intake}, 1, 'daily_intake = 1');
    is($fs->{syndicate}{days_since_purchase}, 0, 'days_since_purchase reset to 0');
};

subtest 'trait saturation reduces price on repeated sales' => sub {
    $season->setCol('faction_state', {});
    $season->save;
    $char->setCol('scrap', 0);
    $char->setCol('score', 0);
    $char->setCol('faction_sales', {});

    my $m = fresh_market();
    my $item1 = $app->shed->create(
        id => 'sat-1', char_id => 'char-1',
        artifact_id => 'thermal_box_001', behaviors => ['thermal'],
        decayed_value => 20, original_value => 20,
    );
    $m->dispatch($char, 'begin');
    my $r1 = $m->dispatch($char, 'offer', shed_item_id => 'sat-1');
    is($r1->{view}{value}, 26, 'sale 1: 20 * 1.1 * 1.2 = 26');

    $m = fresh_market();
    my $item2 = $app->shed->create(
        id => 'sat-2', char_id => 'char-1',
        artifact_id => 'thermal_box_001', behaviors => ['thermal'],
        decayed_value => 20, original_value => 20,
    );
    $m->dispatch($char, 'begin');
    my $r2 = $m->dispatch($char, 'offer', shed_item_id => 'sat-2');
    my $expected2 = int(20 * (1.1 * (1 - 0.10)) * 1.2);
    is($r2->{view}{value}, $expected2, "sale 2 at 10% saturation: $expected2");

    $m = fresh_market();
    my $item3 = $app->shed->create(
        id => 'sat-3', char_id => 'char-1',
        artifact_id => 'thermal_box_001', behaviors => ['thermal'],
        decayed_value => 20, original_value => 20,
    );
    $m->dispatch($char, 'begin');
    my $r3 = $m->dispatch($char, 'offer', shed_item_id => 'sat-3');
    my $expected3 = int(20 * (1.1 * (1 - 0.20)) * 1.2);
    # Sale 3 also triggers appetite penalty (daily_intake=2, appetite_base=2)
    $expected3 = int(20 * (1.1 * (1 - 0.20)) * 0.50 * 1.2);
    is($r3->{view}{value}, $expected3, "sale 3 at 20% saturation + appetite penalty: $expected3");
};

subtest 'daily appetite penalty after threshold' => sub {
    # Set up faction_state where appetite is already exceeded
    $season->setCol('faction_state', {});
    $season->getCol('faction_state')->{syndicate} = {
        name               => 'The Syndicate',
        influence          => 0,
        artifacts_received => 2,
        daily_intake       => 2,
        days_since_purchase => 0,
        intake_by_trait    => { thermal => 2 },
    };
    $season->save;
    $char->setCol('scrap', 0);
    $char->setCol('score', 0);
    $char->setCol('faction_sales', {});

    my $m = fresh_market();
    my $a1 = $app->shed->create(id => 'ap-1', char_id => 'char-1',
        artifact_id => 't1', behaviors => ['thermal'],
        decayed_value => 20, original_value => 20);
    $m->dispatch($char, 'begin');
    my $r1 = $m->dispatch($char, 'offer', shed_item_id => 'ap-1');
    my $expected = int(20 * (1.1 * (1 - 0.20)) * 0.50 * 1.2);
    is($r1->{view}{value}, $expected,
        "post-appetite penalty (sat 20% + penalty 50%): $expected");
};

subtest 'desperation bonus after idle days' => sub {
    $season->setCol('faction_state', {});
    $season->getCol('faction_state')->{syndicate} = {
        name               => 'The Syndicate',
        influence          => 0,
        artifacts_received => 0,
        daily_intake       => 0,
        days_since_purchase => 3,
    };
    $season->save;
    $char->setCol('scrap', 0);
    $char->setCol('score', 0);
    $char->setCol('faction_sales', {});

    my $m = fresh_market();
    my $d1 = $app->shed->create(id => 'des-1', char_id => 'char-1',
        artifact_id => 't1', behaviors => ['thermal'],
        decayed_value => 20, original_value => 20);
    $m->dispatch($char, 'begin');
    my $r1 = $m->dispatch($char, 'offer', shed_item_id => 'des-1');
    my $expected = int(20 * (1.1 * 2.0) * 1.2);
    is($r1->{view}{value}, $expected,
        "desperate faction pays 2x bonus: $expected");
};

subtest 'dynamic_multiplier returns base when no state entry' => sub {
    $season->setCol('faction_state', {});
    $season->save;
    my $m = fresh_market();
    my $dyn = $m->_dynamic_multiplier($season, 'syndicate', ['thermal']);
    # No state entry, no sales → returns base multiplier
    is($dyn, 1.1, 'no state entry returns base_multiplier');
};

subtest 'multi-trait saturation averages across traits' => sub {
    $season->setCol('faction_state', {});
    $season->getCol('faction_state')->{syndicate} = {
        name               => 'The Syndicate',
        influence          => 0,
        artifacts_received => 2,
        daily_intake       => 0,
        days_since_purchase => 0,
        intake_by_trait    => { thermal => 3, power => 1 },
    };
    $season->save;
    my $m = fresh_market();
    my $dyn = $m->_dynamic_multiplier($season, 'syndicate', ['thermal', 'power']);
    my $expected = 1.1 * (1 - 0.40);
    is(sprintf('%.3f', $dyn), sprintf('%.3f', $expected),
        "multi-trait saturation: $dyn (expected $expected)");
};

done_testing;
