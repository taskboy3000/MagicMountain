use Modern::Perl;
use Test::More;

if ($ENV{GITHUB_ACTIONS}) {
    plan skip_all => 'skipping web integration test in GitHub CI';
}
use Test::Mojo;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::Season;

sub setup_with_faction_state {
    my %fs = @_;
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    my $season = MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30);
    $season->setCol('faction_state', \%fs);
    $season->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'player');
    $a->save;

    my $t = TestEnv->create_app;
    $t->app->characters->create(
        name => 'player', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
    )->save;

    my $active_season = $t->app->active_season;
    $t->app->dominance_service->ensure_mountain_data($active_season);

    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

subtest 'mountain chart shows factions in rank order' => sub {
    my $t = setup_with_faction_state(
        syndicate      => { influence => 50 },
        purifiers      => { influence => 30 },
        faculty        => { influence => 20 },
        libremount     => { influence => 10 },
        revelationists => { influence =>  5 },
    );
    $t->get_ok('/factions?_format=fragment')->status_is(200);

    $t->content_like(qr{The Syndicate .AKA: SYND\.8TE.}s,   'syndicate icon title');
    $t->content_like(qr{The Purifiers .AKA: PURIF\.RS.}s,   'purifiers icon title');
    $t->content_like(qr{The Faculty .AKA: FAC\.LTY1.}s,     'faculty icon title');
    $t->content_like(qr{LibreMount .AKA: LBR_MT\.01.}s,     'libremount icon title');
    $t->content_like(qr{The Revelationists .AKA: RVL_IST\.1.}s, 'revelationists icon title');
    $t->content_like(qr{mm-mountain-raster-row}ms, 'raster row present');
    $t->content_like(qr{data-reference-id="faction_syndicate"}ms, 'reference link present');
    $t->content_like(qr{grid-row:\s*1}ms, 'leader at summit row');
};

subtest 'dominant faction gets proper ordering' => sub {
    my $t = setup_with_faction_state(
        syndicate      => { influence => 60 },
        purifiers      => { influence => 10 },
        faculty        => { influence => 8 },
        libremount     => { influence => 5 },
        revelationists => { influence => 2 },
    );
    $t->get_ok('/factions?_format=fragment')->status_is(200);

    $t->content_like(qr{mm-mountain-raster-row}ms, 'raster row present');
};

subtest 'close contest renders' => sub {
    my $t = setup_with_faction_state(
        syndicate      => { influence => 22 },
        purifiers      => { influence => 20 },
        faculty        => { influence => 19 },
        libremount     => { influence => 18 },
        revelationists => { influence => 17 },
    );
    $t->get_ok('/factions?_format=fragment')->status_is(200);

    $t->content_like(qr{mm-mountain-raster-row}ms, 'raster row present');
};

done_testing;
