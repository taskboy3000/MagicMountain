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
        onboarding => 15,
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

    my $t = TestEnv->create_app;
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
        onboarding => 15,
    )->save;

    my $t = TestEnv->create_app;
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
        onboarding => 15,
    )->save;

    my $t = TestEnv->create_app;
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
        onboarding => 15,
    )->save;

    my $t = TestEnv->create_app;
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
        onboarding => 15,
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

    my $t = TestEnv->create_app;
    $t->post_ok('/sessions', json => { displayName => 'trader' })->status_is(200);
    my $csrf = $t->tx->res->json->{csrf_token} // '';
    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);
    return $t;
}

sub _csrf { my $t = shift; $t->tx->res->json->{csrf_token} // '' }

subtest 'idle state — all tabs active' => sub {
    my $t = setup_idle;
    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'home')
      ->json_has('/primary_tabs')
      ->json_has('/primary_fragment_url')
      ->json_has('/secondary_fragment_url')
      ->json_has('/context');

    my $json = $t->tx->res->json;
    for my $tab (@{ $json->{primary_tabs} }) {
        next if $tab->{id} eq q{pawn};
        is $tab->{active}, 1, "tab $tab->{id} is active in idle"
            or diag explain $tab;
        if ($tab->{id} eq 'prospect' || $tab->{id} eq 'bazaar') {
            ok $tab->{action_url}, "tab $tab->{id} has action_url";
        } else {
            ok !exists($tab->{action_url}), "tab $tab->{id} has no action_url";
            ok !exists($tab->{fragment_url}), "tab $tab->{id} has no fragment_url — triggers applyNav, not handleFragmentFetch";
        }
    }
};

subtest 'idle no AP — bazaar inactive' => sub {
    my $t = setup_no_ap;
    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'home');

    my $json = $t->tx->res->json;
    my ($bazaar) = grep { $_->{id} eq 'bazaar' } @{ $json->{primary_tabs} };
    ok !$bazaar->{active}, 'bazaar inactive when no AP';
    is $bazaar->{reason}, 'No AP remaining', 'correct reason';

    my ($prospect) = grep { $_->{id} eq 'prospect' } @{ $json->{primary_tabs} };
    ok !$prospect->{active}, 'prospect inactive when no AP';
    is $prospect->{reason}, 'Not enough AP (2 required)', 'correct reason for prospect';
};

subtest 'idle empty shed — bazaar inactive' => sub {
    my $t = setup_empty_shed;
    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'home');

    my $json = $t->tx->res->json;
    # Shed is empty, AP >= 1 — bazaar inactive due to no items
    my ($bazaar) = grep { $_->{id} eq 'bazaar' } @{ $json->{primary_tabs} };
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
    my ($bazaar) = grep { $_->{id} eq 'bazaar' } @{ $json->{primary_tabs} };
    ok !$bazaar->{active}, 'bazaar inactive during prospecting';
    is $bazaar->{reason}, 'Finish your current expedition first', 'correct reason';
    is $json->{secondary_view}, 'factions', 'secondary is factions during prospecting';
};

subtest 'market visit — prospect inactive' => sub {
    my $t = setup_market;
    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'market')
      ->json_has('/context');

    my $json = $t->tx->res->json;
    my ($prospect) = grep { $_->{id} eq 'prospect' } @{ $json->{primary_tabs} };
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

subtest 'AP=1 — bazaar active but prospect inactive' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'lowap');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'lowap', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 1, action_points_max => 15,
        onboarding => 15,
    )->save;

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

    my $t = TestEnv->create_app;
    $t->post_ok('/sessions', json => { displayName => 'lowap' })->status_is(200);

    $t->get_ok('/nav')
      ->status_is(200);

    my $json = $t->tx->res->json;
    my ($prospect) = grep { $_->{id} eq 'prospect' } @{ $json->{primary_tabs} };
    ok !$prospect->{active}, 'prospect inactive when AP=1 (needs 2)';
    is $prospect->{reason}, 'Not enough AP (2 required)', 'correct reason for prospect';

    my ($bazaar) = grep { $_->{id} eq 'bazaar' } @{ $json->{primary_tabs} };
    ok $bazaar->{active}, 'bazaar active when AP=1';
};

subtest 'X-Nav-View header changes stored view' => sub {
    my $t = setup_idle;

    $t->get_ok('/nav' => {'X-Nav-View' => 'skills'})
      ->status_is(200)
      ->json_is('/current_view', 'skills');

    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'skills', 'stored view persists');
};

subtest 'no activity defaults stored view to home' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'fresh');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'fresh', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
        onboarding => 15,
        # No current_view set — should default to home
    )->save;

    my $t = TestEnv->create_app;
    $t->post_ok('/sessions', json => { displayName => 'fresh' })->status_is(200);

    $t->get_ok('/nav')
      ->status_is(200)
      ->json_is('/current_view', 'home', 'no stored view falls back to home');
};

subtest 'market context text when no active activity returns empty' => sub {
    my $t = setup_idle;
    $t->get_ok('/nav')
      ->status_is(200);

    my $json = $t->tx->res->json;
    # idle state, current_view is home — context should be defined
    ok defined($json->{context}), 'context is defined in idle';
};

subtest 'secondary_tabs include factions, account, orientation, mute' => sub {
    my $t = setup_idle;
    $t->get_ok('/nav')
      ->status_is(200);

    my $json = $t->tx->res->json;
    ok $json->{secondary_tabs}, 'secondary_tabs present';
    is scalar @{ $json->{secondary_tabs} }, 4, 'four secondary tabs with factions';

    my ($factions) = grep { $_->{id} eq 'factions' } @{ $json->{secondary_tabs} };
    ok $factions, 'factions tab present';
    is $factions->{type}, 'nav', 'factions is nav type';

    my ($account) = grep { $_->{id} eq 'account' } @{ $json->{secondary_tabs} };
    ok $account, 'account tab present';
    is $account->{type}, 'nav', 'account is nav type';
    is $account->{target}, 'secondary-content', 'account targets secondary-content';

    my ($orientation) = grep { $_->{id} eq 'orientation' } @{ $json->{secondary_tabs} };
    ok $orientation, 'orientation tab present';
    is $orientation->{type}, 'action', 'orientation is action type';

    my ($mute) = grep { $_->{id} eq 'mute' } @{ $json->{secondary_tabs} };
    ok $mute, 'mute tab present';
    is $mute->{type}, 'toggle', 'mute is toggle type';
    ok exists $mute->{toggle_state}, 'mute has toggle_state';
    ok exists $mute->{key}, 'mute has key field for POST body';
    is $mute->{key}, 'mute', 'mute key matches backend toggle handler';
};

subtest 'primary_tabs do not include account' => sub {
    my $t = setup_idle;
    $t->get_ok('/nav')
      ->status_is(200);

    my $json = $t->tx->res->json;
    my ($account) = grep { $_->{id} eq 'account' } @{ $json->{primary_tabs} };
    ok !$account, 'account not in primary_tabs';
};

subtest 'onboarding — fresh character hides unrevealed tabs' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'fresh');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'fresh', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
        onboarding => 0,
    )->save;

    my $t = TestEnv->create_app;
    $t->post_ok('/sessions', json => { displayName => 'fresh' })->status_is(200);

    $t->get_ok('/nav')
      ->status_is(200);

    my $json = $t->tx->res->json;
    my @present = map { $_->{id} } @{ $json->{primary_tabs} };
    ok !grep({ $_ eq 'bazaar' } @present), 'bazaar hidden for fresh character'
        or diag explain $json->{primary_tabs};
    ok !grep({ $_ eq 'pvp' } @present), 'pvp hidden for fresh character'
        or diag explain $json->{primary_tabs};
    ok !grep({ $_ eq 'skills' } @present), 'skills hidden for fresh character'
        or diag explain $json->{primary_tabs};
    ok grep({ $_ eq 'home' } @present), 'home present for fresh character';
    ok grep({ $_ eq 'prospect' } @present), 'prospect present for fresh character';

    my @secondary = map { $_->{id} } @{ $json->{secondary_tabs} };
    ok !grep({ $_ eq 'factions' } @secondary), 'factions hidden for fresh character';
    ok grep({ $_ eq 'account' } @secondary), 'account present for fresh character';
};

subtest 'onboarding — bazaar revealed with shed item' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'shedder');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'shedder', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
        onboarding => 1,  # BIT_BAZAAR only
    )->save;

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

    my $t = TestEnv->create_app;
    $t->post_ok('/sessions', json => { displayName => 'shedder' })->status_is(200);

    $t->get_ok('/nav')
      ->status_is(200);

    my $json = $t->tx->res->json;
    my @present = map { $_->{id} } @{ $json->{primary_tabs} };
    ok grep({ $_ eq 'bazaar' } @present), 'bazaar present for shedder';
    ok !grep({ $_ eq 'skills' } @present), 'skills still hidden';
    ok !grep({ $_ eq 'pvp' } @present), 'pvp still hidden';
};

subtest 'toggle mute flips settings_muted' => sub {
    my $t = setup_idle;
    my $csrf = _csrf($t);

    my $json = $t->tx->res->json;
    my ($mute_before) = grep { $_->{id} eq 'mute' } @{ $json->{secondary_tabs} };
    my $before = $mute_before->{toggle_state};

    $t->post_ok('/nav/toggle' => {'X-CSRF-Token' => $csrf} => json => { key => 'mute' })
      ->status_is(200);

    my $after_json = $t->tx->res->json;
    my ($mute_after) = grep { $_->{id} eq 'mute' } @{ $after_json->{secondary_tabs} };
    is $mute_after->{toggle_state}, $before ? 0 : 1, 'toggle_state flipped';
};

done_testing();
