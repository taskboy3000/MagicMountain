use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::ShedItem;
use MagicMountain::Model::Season;

sub setup_idle {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'player');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'player', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
    )->save;

    # Add a shed item so bazaar is active
    my ($char) = @{ $chars->find(sub { $_[0]->{account_id} eq $a->getCol('id') }) };
    my $shed = MagicMountain::Model::ShedItem->new(file => "$dataDir/shed.json");
    $shed->create(
        char_id => $char->getCol('id'), artifact_id => 'test_cog',
        original_value => 10, decayed_value => 10,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => ['thermal'],
        estimated_value_min => 8, estimated_value_max => 12,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

sub setup_no_ap {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'tired');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'tired', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 0, action_points_max => 15,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'tired' })->status_is(200);
    return $t;
}

sub setup_empty_shed {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'empty');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'empty', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'empty' })->status_is(200);
    return $t;
}

sub setup_prospecting {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'prospector');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'prospector', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'prospector' })->status_is(200);
    my $csrf = $t->tx->res->json->{csrf_token} // '';
    $t->post_ok('/prospecting/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);
    return $t;
}

sub setup_market {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'trader');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'trader', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
    )->save;

    # Shed item needed for market visit
    my ($char) = @{ $chars->find(sub { $_[0]->{account_id} eq $a->getCol('id') }) };
    my $shed = MagicMountain::Model::ShedItem->new(file => "$dataDir/shed.json");
    $shed->create(
        char_id => $char->getCol('id'), artifact_id => 'test_cog',
        original_value => 10, decayed_value => 10,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => ['thermal'],
        estimated_value_min => 8, estimated_value_max => 12,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'trader' })->status_is(200);
    my $csrf = $t->tx->res->json->{csrf_token} // '';
    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);
    return $t;
}

subtest 'idle state — all tabs active' => sub {
    my $t = setup_idle;
    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'idle')
      ->json_has('/tabs')
      ->json_has('/primary_fragment_url')
      ->json_has('/secondary_fragment_url')
      ->json_has('/context');

    my $json = $t->tx->res->json;
    for my $tab (@{ $json->{tabs} }) {
        is $tab->{active}, 1, "tab $tab->{id} is active in idle"
            or diag explain $tab;
        like $tab->{fragment_url}, qr{^/}, "tab $tab->{id} has fragment_url";
    }
};

subtest 'idle no AP — bazaar inactive' => sub {
    my $t = setup_no_ap;
    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'idle');

    my $json = $t->tx->res->json;
    my ($bazaar) = grep { $_->{id} eq 'bazaar' } @{ $json->{tabs} };
    ok !$bazaar->{active}, 'bazaar inactive when no AP';
    is $bazaar->{reason}, 'No AP remaining', 'correct reason';

    my ($prospect) = grep { $_->{id} eq 'prospect' } @{ $json->{tabs} };
    ok !$prospect->{active}, 'prospect inactive when no AP';
    is $prospect->{reason}, 'Not enough AP (2 required)', 'correct reason for prospect';
};

subtest 'idle empty shed — bazaar inactive' => sub {
    my $t = setup_empty_shed;
    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'idle');

    my $json = $t->tx->res->json;
    # Shed is empty, AP >= 1 — bazaar inactive due to no items
    my ($bazaar) = grep { $_->{id} eq 'bazaar' } @{ $json->{tabs} };
    ok !$bazaar->{active}, 'bazaar inactive when shed empty';
    is $bazaar->{reason}, 'No artifacts in shed', 'correct reason';
};

subtest 'prospecting — bazaar inactive' => sub {
    my $t = setup_prospecting;
    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'prospecting')
      ->json_has('/context');

    my $json = $t->tx->res->json;
    my ($bazaar) = grep { $_->{id} eq 'bazaar' } @{ $json->{tabs} };
    ok !$bazaar->{active}, 'bazaar inactive during prospecting';
    is $bazaar->{reason}, 'Finish your current expedition first', 'correct reason';
    is $json->{secondary_view}, 'shed', 'secondary is shed during prospecting';
};

subtest 'market visit — prospect inactive' => sub {
    my $t = setup_market;
    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'market')
      ->json_has('/context');

    my $json = $t->tx->res->json;
    my ($prospect) = grep { $_->{id} eq 'prospect' } @{ $json->{tabs} };
    ok !$prospect->{active}, 'prospect inactive during market';
    is $prospect->{reason}, 'Complete your market visit first', 'correct reason';
    is $json->{secondary_view}, 'shed', 'secondary is shed during market';
};

subtest 'prospecting context text' => sub {
    my $t = setup_prospecting;
    $t->get_ok('/nav')
      ->status_is(200);

    my $json = $t->tx->res->json;
    like $json->{context}, qr/INSTABILITY/, 'context contains instability';
    like $json->{context}, qr/STAGE/, 'context contains stage';
    like $json->{context}, qr/VALUE/, 'context contains value';
};

subtest 'market context text' => sub {
    my $t = setup_market;
    $t->get_ok('/nav')
      ->status_is(200);

    my $json = $t->tx->res->json;
    like $json->{context}, qr/BUYER/, 'context contains buyer';
    like $json->{context}, qr/IRRITATION/, 'context contains irritation';
    like $json->{context}, qr/MOOD/, 'context contains mood';
};

subtest 'idle context text' => sub {
    my $t = setup_idle;
    $t->get_ok('/nav')
      ->status_is(200);

    my $json = $t->tx->res->json;
    ok defined $json->{context}, 'context is defined';
};

done_testing;
