use Modern::Perl;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Service::Dominance;
use MagicMountain::Model::Season;

{
    package FakeApp;
    sub new { bless {}, shift }
    sub factions_data {
        return [
            { id => 'syndicate',      name => 'The Syndicate',      climate => {} },
            { id => 'purifiers',      name => 'The Purifiers',      climate => {} },
            { id => 'faculty',        name => 'The Faculty',        climate => {} },
        ];
    }
}

sub _make_season {
    my ($faction_state) = @_;
    my $dataDir = tempdir(CLEANUP => 1);
    my $season = MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 'test', label => 'Test', status => 'active', day => 7, length => 30);
    $season->setCol('faction_state', $faction_state);
    $season->save;
    return $season;
}

my $dom = MagicMountain::Service::Dominance->new(app => FakeApp->new);

subtest 'fresh season with no faction_climate computes and persists' => sub {
    my $season = _make_season({
        syndicate      => { influence => 50 },
        purifiers      => { influence => 30 },
        faculty        => { influence => 20 },
    });

    $dom->ensure_mountain_data($season);
    my $fc = $season->faction_climate;

    ok($fc->{mountain_positions}, 'mountain_positions computed');
    ok($fc->{mountain_height},    'mountain_height set');
    ok($fc->{mountain_raster},    'mountain_raster computed');

    is(scalar @{$fc->{mountain_positions}}, 3, 'three factions positioned');
    is($fc->{mountain_positions}[0]{row_offset}, 1, 'leader at summit');
    is($fc->{day}, 7, 'day matches season day');
    is($fc->{intensity}, 'strong', 'intensity computed from faction_state');
    is($fc->{dominant_faction}, 'syndicate', 'dominant_faction synced from faction_state');
    is($fc->{dominant_faction_name}, 'The Syndicate', 'dominant_faction_name synced');

    my $expected_rows = $fc->{mountain_height};
    is(scalar @{$fc->{mountain_raster}}, $expected_rows, 'raster has one row per mountain height');
};

subtest 'existing faction_climate without mountain keys backfills' => sub {
    my $season = _make_season({
        syndicate => { influence => 60 },
        purifiers => { influence => 10 },
    });
    $season->setCol('faction_climate', {
        day              => 7,
        intensity        => 'leading',
        intensity_label  => 'Leading',
        dominance_margin => 50,
    });
    $season->save;

    $dom->ensure_mountain_data($season);
    my $fc = $season->faction_climate;

    ok($fc->{mountain_positions}, 'mountain_positions added to existing climate');
    ok($fc->{mountain_raster},    'mountain_raster added');
    is($fc->{intensity}, 'dominant', 'intensity recomputed from faction_state');
    is($fc->{day}, 7, 'day synced from season');
    is($fc->{dominant_faction}, 'syndicate', 'dominant_faction synced from faction_state');
    is($fc->{dominant_faction_name}, 'The Syndicate', 'dominant_faction_name synced');

    my $expected_rows = $fc->{mountain_height};
    is(scalar @{$fc->{mountain_raster}}, $expected_rows, 'raster row count matches height');
};

subtest 'already consistent — no-op fast path' => sub {
    my $season = _make_season({
        syndicate => { influence => 60 },
        purifiers => { influence => 10 },
    });
    $season->setCol('faction_climate', {
        day                  => 7,
        dominant_faction     => 'syndicate',
        dominant_faction_name => 'The Syndicate',
        intensity            => 'leading',
        intensity_label      => 'Leading',
        dominance_margin     => 50,
        mountain_positions   => [{ faction_id => 'syndicate', row_offset => 1 }],
        mountain_height      => 10,
        mountain_raster      => ["\x{2588}" x 19],
    });
    $season->save;
    my $original_raster = $season->faction_climate->{mountain_raster};

    $dom->ensure_mountain_data($season);

    is_deeply($season->faction_climate->{mountain_raster}, $original_raster,
        'raster unchanged when already consistent');
};

subtest 'stale dominant_faction corrected when faction_state leader changes' => sub {
    my $season = _make_season({
        syndicate => { influence => 60 },
        purifiers => { influence => 10 },
    });
    $season->setCol('faction_climate', {
        day                  => 7,
        dominant_faction     => 'purifiers',
        dominant_faction_name => 'The Purifiers',
        dominance_margin     => 50,
        intensity            => 'dominant',
        intensity_label      => 'Dominant',
        mountain_positions   => [{ faction_id => 'purifiers', row_offset => 1 }],
        mountain_height      => 10,
        mountain_raster      => ["\x{2588}" x 19],
    });
    $season->save;

    $dom->ensure_mountain_data($season);

    my $fc = $season->faction_climate;
    is($fc->{dominant_faction}, 'syndicate',
        'dominant_faction corrected to real leader');
    is($fc->{dominant_faction_name}, 'The Syndicate',
        'dominant_faction_name corrected');
    is($fc->{mountain_positions}[0]{faction_id}, 'syndicate',
        'mountain_positions leader corrected to real leader');
};

subtest 'contested tier still produces a mountain' => sub {
    my $season = _make_season({
        syndicate => { influence => 22 },
        purifiers => { influence => 20 },
        faculty   => { influence => 19 },
    });

    $dom->ensure_mountain_data($season);
    my $fc = $season->faction_climate;

    ok($fc->{mountain_raster}, 'raster computed for contested tier');
    ok(scalar @{$fc->{mountain_raster}} > 0, 'raster non-empty');
    is($fc->{intensity}, 'contested', 'tier is contested');
    ok($fc->{mountain_positions}[0]{row_offset} == 1, 'leader still at summit');
};

subtest 'mountain_height adapts to lowest faction position' => sub {
    my $season = _make_season({
        A => { influence => 60 },
        B => { influence => 55 },
        C => { influence => 50 },
        D => { influence => 45 },
        E => { influence => 5 },
    });

    $dom->ensure_mountain_data($season);
    my $fc = $season->faction_climate;

    my $lowest_row = 1;
    for my $p (@{$fc->{mountain_positions}}) {
        $lowest_row = $p->{row_offset} if $p->{row_offset} > $lowest_row;
    }
    is($fc->{mountain_height}, $lowest_row, 'height matches lowest faction row');
    is(scalar @{$fc->{mountain_raster}}, $lowest_row, 'raster row count matches height');
};

done_testing;
