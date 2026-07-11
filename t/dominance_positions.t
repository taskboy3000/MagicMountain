use Modern::Perl;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Service::Dominance;
use MagicMountain::Model::Season;

sub _make_season {
    my ($faction_state) = @_;
    my $dataDir = tempdir(CLEANUP => 1);
    my $season = MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 'test', label => 'Test', status => 'active', day => 1, length => 30);
    $season->setCol('faction_state', $faction_state);
    $season->save;
    return $season;
}

subtest 'spread influence uses proportional positions' => sub {
    my $season = _make_season({
        A => { influence => 100 },
        B => { influence => 50 },
        C => { influence => 25 },
    });
    my $dom = MagicMountain::Service::Dominance->new(app => bless({}, 'UNIVERSAL'));
    my $pos = $dom->faction_positions($season);

    is(scalar @$pos, 3, 'three factions');
    is($pos->[0]{row_offset}, 1,  'leader at summit (row 1)');
    is($pos->[1]{row_offset}, 12, '50% influence at row 12');
    is($pos->[2]{row_offset}, 17, '25% influence at row 17');
};

subtest 'clustered influence falls back to even distribution' => sub {
    my $season = _make_season({
        A => { influence => 100 },
        B => { influence => 98 },
        C => { influence => 97 },
    });
    my $dom = MagicMountain::Service::Dominance->new(app => bless({}, 'UNIVERSAL'));
    my $pos = $dom->faction_positions($season);

    is(scalar @$pos, 3, 'three factions');
    ok($pos->[1]{row_offset} - $pos->[0]{row_offset} >= 2, 'minimum 2-row gap between A and B');
    ok($pos->[2]{row_offset} - $pos->[1]{row_offset} >= 2, 'minimum 2-row gap between B and C');
    is($pos->[0]{row_offset}, 1, 'leader still at summit');
};

subtest 'five factions with tight cluster uses even distribution' => sub {
    my $season = _make_season({
        A => { influence => 22 },
        B => { influence => 20 },
        C => { influence => 19 },
        D => { influence => 18 },
        E => { influence => 17 },
    });
    my $dom = MagicMountain::Service::Dominance->new(app => bless({}, 'UNIVERSAL'));
    my $pos = $dom->faction_positions($season);

    is(scalar @$pos, 5, 'five factions');
    my @rows = sort { $a <=> $b } map { $_->{row_offset} } @$pos;
    is_deeply(\@rows, [1, 6, 12, 17, 22], 'evenly distributed across 22 rows');
};

subtest 'single faction returns just the leader' => sub {
    my $season = _make_season({ A => { influence => 100 } });
    my $dom = MagicMountain::Service::Dominance->new(app => bless({}, 'UNIVERSAL'));
    my $pos = $dom->faction_positions($season);

    is(scalar @$pos, 1, 'one faction');
    is($pos->[0]{row_offset}, 1, 'at summit');
};

subtest 'no faction state returns empty' => sub {
    my $season = _make_season({});
    my $dom = MagicMountain::Service::Dominance->new(app => bless({}, 'UNIVERSAL'));
    my $pos = $dom->faction_positions($season);

    is_deeply($pos, [], 'empty result');
};

subtest 'variable total_rows parameter' => sub {
    my $season = _make_season({
        A => { influence => 100 },
        B => { influence => 50 },
        C => { influence => 25 },
    });
    my $dom = MagicMountain::Service::Dominance->new(app => bless({}, 'UNIVERSAL'));

    my $pos10 = $dom->faction_positions($season, 10);
    is($pos10->[0]{row_offset}, 1, 'leader at summit with 10 rows');
    is($pos10->[1]{row_offset}, 6, '50% influence at row 6 with 10 rows');
    is($pos10->[2]{row_offset}, 8, '25% influence at row 8 with 10 rows');

    my $pos15 = $dom->faction_positions($season, 15);
    is($pos15->[0]{row_offset}, 1, 'leader at summit with 15 rows');
    is($pos15->[1]{row_offset}, 8, '50% influence at row 8 with 15 rows');
    is($pos15->[2]{row_offset}, 12, '25% influence at row 12 with 15 rows');
};

done_testing;
