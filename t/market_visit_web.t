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

    my $char = $chars->find(sub { 1 })->[0];
    my $char_id = $char->getCol('id');

    # Add a shed item so market begin works
    my $shed = MagicMountain::Model::ShedItem->new(file => "$dataDir/shed.json");
    $shed->create(
        char_id => $char_id,
        artifact_id => 'thermal_box_001',
        original_value => 20, decayed_value => 20,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => ['thermal'],
        estimated_value_min => 16, estimated_value_max => 24,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

sub _csrf { my $t = shift; $t->tx->res->json->{csrf_token} // '' }

subtest 'unauthenticated redirects' => sub {
    my $t = setup;
    $t->delete_ok('/sessions')->status_is(200);
    $t->post_ok('/market/begin')
      ->status_is(302)
      ->header_like(Location => qr{/login});
};

subtest 'begin — starts a market visit' => sub {
    my $t = setup;
    my $csrf = _csrf($t);
    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/result' => 'negotiating')
      ->json_has('/customer/faction_id');
};

subtest 'full lifecycle: begin → offer → sale' => sub {
    my $t = setup;
    my $csrf = _csrf($t);

    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200)->json_is('/ok' => 1);

    my $char = $t->app->characters->find(sub { 1 })->[0];
    my $shed_items = $t->app->shed->find(sub { $_[0]->{char_id} eq $char->getCol('id') });
    my $shed_item_id = $shed_items->[0]->getCol('id');

    $t->post_ok('/market/offer' => {'X-CSRF-Token' => $csrf}, json => { shed_item_id => $shed_item_id })
      ->status_is(200);
    my $result = $t->tx->res->json->{result};
    ok($result, "offer returned result: $result");

    if ($result eq 'sold') {
        my $disc = $t->app->disposition;
        my $all = $disc->find(sub { 1 });
        is(scalar @$all, 1, 'disposition record created on sale');
        is($all->[0]->getCol('value_awarded'), $t->tx->res->json->{value},
            'disposition value matches sale value');
    }
};

subtest 'counter-offer generated on mismatch' => sub {
    my $t = setup;
    $t->app->config->{market_counter_offers} = 1;
    my $csrf = _csrf($t);

    my $char = $t->app->characters->find(sub { 1 })->[0];
    my $char_id = $char->getCol('id');

    # Add item with 'defense' behavior — no faction desires it
    my $shed = $t->app->shed;
    $shed->create(
        char_id => $char_id, artifact_id => 'defense_item',
        original_value => 20, decayed_value => 20,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => ['defense'],
        estimated_value_min => 16, estimated_value_max => 24,
    )->save;

    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    # Disable settlement to make counter-offer deterministic
    $char = $t->app->characters->find(sub { 1 })->[0];
    my $act = $t->app->market->get($char->getCol('pending_activity_id'));
    $act->customer->{settle_chance} = 0;
    $act->save;

    my $items = $t->app->shed->find(sub { $_[0]->{char_id} eq $char_id && $_[0]->{artifact_id} eq 'defense_item' });
    my $shed_item_id = $items->[0]->getCol('id');

    $t->post_ok('/market/offer' => {'X-CSRF-Token' => $csrf}, json => { shed_item_id => $shed_item_id })
      ->status_is(200)
      ->json_is('/result' => 'counter_offer')
      ->json_has('/counter_value')
      ->json_has('/irritation')
      ->json_is('/irritation' => 0);
};

subtest 'accept_counter sells at counter price' => sub {
    my $t = setup;
    $t->app->config->{market_counter_offers} = 1;
    my $csrf = _csrf($t);

    my $char = $t->app->characters->find(sub { 1 })->[0];
    my $char_id = $char->getCol('id');

    my $shed = $t->app->shed;
    $shed->create(
        char_id => $char_id, artifact_id => 'defense_item',
        original_value => 20, decayed_value => 20,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => ['defense'],
        estimated_value_min => 16, estimated_value_max => 24,
    )->save;

    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    # Disable settlement to make counter deterministic
    $char = $t->app->characters->find(sub { 1 })->[0];
    my $act = $t->app->market->get($char->getCol('pending_activity_id'));
    $act->customer->{settle_chance} = 0;
    $act->save;

    my $items = $t->app->shed->find(sub { $_[0]->{char_id} eq $char_id && $_[0]->{artifact_id} eq 'defense_item' });
    my $shed_item_id = $items->[0]->getCol('id');

    $t->post_ok('/market/offer' => {'X-CSRF-Token' => $csrf}, json => { shed_item_id => $shed_item_id })
      ->status_is(200)
      ->json_is('/result' => 'counter_offer');

    my $counter_value = $t->tx->res->json->{counter_value};

    $t->post_ok('/market/accept_counter' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/result' => 'sold')
      ->json_is('/value' => $counter_value);

    my $disc = $t->app->disposition;
    my $all = $disc->find(sub { 1 });
    is(scalar @$all, 1, 'disposition record created on counter sale');
    is($all->[0]->getCol('value_awarded'), $counter_value,
        'disposition value matches counter value');
};

subtest 'counter-offer visible in game state' => sub {
    my $t = setup;
    $t->app->config->{market_counter_offers} = 1;
    my $csrf = _csrf($t);

    my $char = $t->app->characters->find(sub { 1 })->[0];
    my $char_id = $char->getCol('id');

    my $shed = $t->app->shed;
    $shed->create(
        char_id => $char_id, artifact_id => 'defense_item',
        original_value => 20, decayed_value => 20,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => ['defense'],
        estimated_value_min => 16, estimated_value_max => 24,
    )->save;

    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    # Disable settlement to make counter deterministic
    $char = $t->app->characters->find(sub { 1 })->[0];
    my $act = $t->app->market->get($char->getCol('pending_activity_id'));
    $act->customer->{settle_chance} = 0;
    $act->save;

    my $items = $t->app->shed->find(sub { $_[0]->{char_id} eq $char_id && $_[0]->{artifact_id} eq 'defense_item' });
    my $shed_item_id = $items->[0]->getCol('id');

    $t->post_ok('/market/offer' => {'X-CSRF-Token' => $csrf}, json => { shed_item_id => $shed_item_id })
      ->status_is(200)
      ->json_is('/result' => 'counter_offer');

    $t->get_ok('/game' => {'Accept' => 'application/json'})
      ->status_is(200)
      ->json_has('/market_visit/customer/pending_counter')
      ->json_has('/market_visit/customer/pending_counter/value');
};

subtest 'multi-item allows multiple sales' => sub {
    my $t = setup;
    $t->app->config->{market_multi_item} = 1;
    my $csrf = _csrf($t);

    my $char = $t->app->characters->find(sub { 1 })->[0];
    my $char_id = $char->getCol('id');

    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    # Get the customer's desired behaviors and create matching items
    $char = $t->app->characters->find(sub { 1 })->[0];
    my $act_id = $char->getCol('pending_activity_id');
    my $activity = $t->app->market->get($act_id);
    my $customer = $activity->customer;
    my $match_behavior = $customer->{desired_behaviors}[0];

    my $shed = $t->app->shed;
    for my $i (1 .. 2) {
        $shed->create(
            char_id => $char_id, artifact_id => "match_item_$i",
            original_value => 20, decayed_value => 20,
            condition => 'fresh', days_in_shed => 0,
            instability => 0, stage => 'stable', push_count => 0,
            has_evolved => 0, behaviors => [$match_behavior],
            estimated_value_min => 16, estimated_value_max => 24,
        )->save;
    }

    my $items = $t->app->shed->find(sub { $_[0]->{char_id} eq $char_id && $_[0]->{artifact_id} =~ /^match_item_/ });
    my @sorted = sort { $a->getCol('artifact_id') cmp $b->getCol('artifact_id') } @$items;

    # First sale
    $t->post_ok('/market/offer' => {'X-CSRF-Token' => $csrf},
        json => { shed_item_id => $sorted[0]->getCol('id') })
      ->status_is(200)
      ->json_is('/result' => 'sold_more')
      ->json_has('/value')
      ->json_has('/irritation')
      ->json_has('/message');

    # Second sale
    $t->post_ok('/market/offer' => {'X-CSRF-Token' => $csrf},
        json => { shed_item_id => $sorted[1]->getCol('id') })
      ->status_is(200)
      ->json_is('/result' => 'sold_more')
      ->json_has('/value');

    # Send away
    $t->post_ok('/market/send_away' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/result' => 'sent_away');

    my $remaining = $t->app->shed->find(sub { $_[0]->{char_id} eq $char_id && $_[0]->{artifact_id} =~ /^match_item_/ });
    is(scalar @$remaining, 0, 'both match items sold from shed');
};

subtest 'send_away works' => sub {
    my $t = setup;
    my $csrf = _csrf($t);

    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    $t->post_ok('/market/send_away' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/result' => 'sent_away');

    my $char = $t->app->characters->find(sub { 1 })->[0];
    is($char->getCol('pending_activity_id'), undef, 'activity cleared after send_away');
};

subtest 'customer_left when irritation threshold hit' => sub {
    my $t = setup;
    $t->app->config->{market_counter_offers} = 0;
    my $csrf = _csrf($t);

    my $char = $t->app->characters->find(sub { 1 })->[0];
    my $char_id = $char->getCol('id');

    my $shed = $t->app->shed;
    $shed->create(
        char_id => $char_id, artifact_id => 'defense_item',
        original_value => 20, decayed_value => 20,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => ['defense'],
        estimated_value_min => 16, estimated_value_max => 24,
    )->save;

    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    # Disable settlement to make mismatches deterministic
    $char = $t->app->characters->find(sub { 1 })->[0];
    my $act_id = $char->getCol('pending_activity_id');
    my $activity = $t->app->market->get($act_id);
    $activity->customer->{settle_chance} = 0;
    $activity->save;

    my $items = $t->app->shed->find(sub { $_[0]->{char_id} eq $char_id && $_[0]->{artifact_id} eq 'defense_item' });
    my $shed_item_id = $items->[0]->getCol('id');

    # 4 mismatches = irritation 4 (threshold is 5)
    for (1 .. 4) {
        $t->post_ok('/market/offer' => {'X-CSRF-Token' => $csrf},
            json => { shed_item_id => $shed_item_id })
          ->status_is(200)
          ->json_is('/result' => 'no_match');
    }

    # 5th mismatch → irritation hits 5 → customer_left
    $t->post_ok('/market/offer' => {'X-CSRF-Token' => $csrf},
        json => { shed_item_id => $shed_item_id })
      ->status_is(200)
      ->json_is('/result' => 'customer_left');

    my $char2 = $t->app->characters->find(sub { 1 })->[0];
    is($char2->getCol('pending_activity_id'), undef, 'activity cleared after customer_left');
};

done_testing;
