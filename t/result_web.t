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

sub setup {
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

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

sub _csrf { my $t = shift; $t->tx->res->json->{csrf_token} // '' }

subtest 'no result — returns 204' => sub {
    my $t = setup;
    $t->get_ok('/result?_format=fragment')->status_is(204);
    $t->get_ok('/result')->status_is(204);
};

subtest 'dismiss with no result — still ok' => sub {
    my $t = setup;
    my $csrf = _csrf($t);
    $t->post_ok('/result/dismiss' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/ok' => 1);
};

subtest 'show fragment when result set on character' => sub {
    my $t = setup;
    my $chars = $t->app->characters;
    $chars->load;
    my ($char) = @{ $chars->find(sub { $_[0]->{account_id} ne '' }) };
    $char->setCol('result', {
        outcome      => 'sold',
        icon         => 'SCRAP',
        outcome_text => 'Sold!',
        value        => 42,
        message      => 'Sold to Test Faction for 42 scrap.',
        item_name    => 'thermal_box_001',
    });
    $char->setCol('current_view', 'result');
    $char->save;

    $t->get_ok('/result?_format=fragment')
      ->status_is(200)
      ->content_like(qr{RESULT}, 'fragment has RESULT header')
      ->content_like(qr{SCRAP}, 'fragment has SCRAP icon')
      ->content_like(qr{Sold!}, 'fragment has outcome text')
      ->content_like(qr{thermal_box_001}, 'fragment has item name')
      ->content_like(qr{42}, 'fragment has value')
      ->content_like(qr{Sold to Test Faction}, 'fragment has message')
      ->content_like(qr{/result/dismiss}, 'fragment has dismiss button');
};

subtest 'show fragment without value — value row omitted' => sub {
    my $t = setup;
    my $chars = $t->app->characters;
    $chars->load;
    my ($char) = @{ $chars->find(sub { $_[0]->{account_id} ne '' }) };
    $char->setCol('result', {
        outcome      => 'customer_left',
        icon         => 'ALERT',
        outcome_text => 'Customer Stormed Off',
        message      => 'The buyer storms off.',
        item_name    => 'thermal_box_001',
    });
    $char->setCol('current_view', 'result');
    $char->save;

    $t->get_ok('/result?_format=fragment')
      ->status_is(200)
      ->content_like(qr{Customer Stormed Off}, 'fragment has outcome text')
      ->content_unlike(qr{scrap}, 'fragment omits value line');
};

subtest 'dismiss clears result and restores nav to home' => sub {
    my $t = setup;
    my $chars = $t->app->characters;
    $chars->load;
    my ($char) = @{ $chars->find(sub { $_[0]->{account_id} ne '' }) };
    $char->setCol('result', {
        outcome      => 'collapse',
        icon         => 'ALERT',
        outcome_text => 'Artifact Collapsed',
        message      => 'The artifact crumbles.',
        item_name    => 'strange_crystal',
    });
    $char->setCol('current_view', 'result');
    $char->save;

    my $csrf = _csrf($t);

    $t->post_ok('/result/dismiss' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/ok' => 1);

    $t->get_ok('/result?_format=fragment')->status_is(204);

    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'home');
};

subtest 'nav returns result view when current_view is result' => sub {
    my $t = setup;
    my $chars = $t->app->characters;
    $chars->load;
    my ($char) = @{ $chars->find(sub { $_[0]->{account_id} ne '' }) };
    $char->setCol('result', {
        outcome      => 'breakthrough',
        icon         => 'PREMIUM',
        outcome_text => 'Breakthrough!',
        value        => 100,
        message      => 'A sudden breakthrough!',
        item_name    => 'ancient_relic',
    });
    $char->setCol('current_view', 'result');
    $char->save;

    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'result')
      ->json_is('/primary_fragment_url', '/result?_format=fragment')
      ->json_is('/secondary_view', 'factions')
      ->json_has('/primary_tabs');

    my $json = $t->tx->res->json;
    my ($home_tab) = grep { $_->{id} eq 'home' } @{ $json->{primary_tabs} };
    ok $home_tab->{current}, 'home tab highlighted when viewing result';
};

subtest 'unauthenticated redirects' => sub {
    my $t = setup;
    $t->delete_ok('/sessions')->status_is(200);
    $t->get_ok('/result?_format=fragment')
      ->status_is(302)
      ->header_like(Location => qr{/login});
};

subtest 'do_continue — no result returns 400' => sub {
    my $t = setup;
    my $csrf = _csrf($t);
    $t->post_ok('/result/continue' => {'X-CSRF-Token' => $csrf})
      ->status_is(400)
      ->json_is('/ok' => 0)
      ->json_is('/error' => 'no result');
};

subtest 'do_continue — unknown outcome returns 400' => sub {
    my $t = setup;
    my $chars = $t->app->characters;
    $chars->load;
    my ($char) = @{ $chars->find(sub { $_[0]->{account_id} ne '' }) };
    $char->setCol('result', {
        outcome      => 'unknown_outcome',
        outcome_text => '???',
        message      => 'Something happened.',
    });
    $char->setCol('current_view', 'result');
    $char->save;

    my $csrf = _csrf($t);
    $t->post_ok('/result/continue' => {'X-CSRF-Token' => $csrf})
      ->status_is(400)
      ->json_is('/ok' => 0)
      ->json_is('/error' => 'cannot continue from this outcome');
};

subtest 'do_continue — insufficient AP returns 400' => sub {
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
        score => 0, scrap => 0, action_points => 0, action_points_max => 15,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);

    $chars->load;
    my ($char) = @{ $chars->find(sub { $_[0]->{account_id} ne '' }) };
    $char->setCol('result', {
        outcome      => 'stopped',
        outcome_text => 'Stopped',
        value        => 24,
        message      => 'Artifact secured.',
        item_name    => 'thermal_box_001',
    });
    $char->setCol('current_view', 'result');
    $char->save;

    my $csrf = _csrf($t);
    $t->post_ok('/result/continue' => {'X-CSRF-Token' => $csrf})
      ->status_is(400)
      ->json_is('/ok' => 0)
      ->json_is('/error' => 'insufficient resources');
};

subtest 'do_continue — prospecting outcome begins new prospecting' => sub {
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

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);

    $chars->load;
    my ($char) = @{ $chars->find(sub { $_[0]->{account_id} ne '' }) };
    $char->setCol('result', {
        outcome      => 'stopped',
        outcome_text => 'Stopped',
        value        => 24,
        message      => 'Artifact secured.',
        item_name    => 'thermal_box_001',
    });
    $char->setCol('current_view', 'result');
    $char->save;

    my $csrf = _csrf($t);
    $t->post_ok('/result/continue' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/ok' => 1);

    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'prospecting');
};

subtest 'do_continue — market outcome begins new market visit' => sub {
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
        score => 0, scrap => 200, action_points => 15, action_points_max => 15,
    )->save;

    my $shed = MagicMountain::Model::ShedItem->new(file => "$dataDir/shed.json");
    $shed->create(
        char_id => $chars->find(sub { 1 })->[0]->getCol('id'),
        artifact_id => 'thermal_box_001', original_value => 24,
        decayed_value => 24, condition => 'fresh', days_in_shed => 0,
        instability => 5, stage => 'strained', push_count => 2,
        has_evolved => 0, behaviors => ['thermal'], archetypes => ['energy'],
        estimated_value_min => 19, estimated_value_max => 29,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);

    $chars->load;
    my ($char) = @{ $chars->find(sub { $_[0]->{account_id} ne '' }) };
    $char->setCol('result', {
        outcome      => 'sold',
        outcome_text => 'Sold!',
        value        => 42,
        message      => 'Sold to Test Faction.',
        item_name    => 'thermal_box_001',
    });
    $char->setCol('current_view', 'result');
    $char->save;

    my $csrf = _csrf($t);
    $t->post_ok('/result/continue' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/ok' => 1);

    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'market');
};

subtest 'show — JSON response shape' => sub {
    my $t = setup;
    my $chars = $t->app->characters;
    $chars->load;
    my ($char) = @{ $chars->find(sub { $_[0]->{account_id} ne '' }) };
    $char->setCol('result', {
        outcome      => 'collapse',
        icon         => 'ALERT',
        outcome_text => 'Artifact Collapsed',
        value        => 0,
        message      => 'The artifact crumbles to dust.',
        item_name    => 'strange_crystal',
    });
    $char->setCol('current_view', 'result');
    $char->save;

    $t->get_ok('/result')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/result/outcome' => 'collapse')
      ->json_is('/result/outcome_text' => 'Artifact Collapsed')
      ->json_is('/result/value' => 0)
      ->json_is('/result/item_name' => 'strange_crystal')
      ->json_has('/can_continue');
};

done_testing;
