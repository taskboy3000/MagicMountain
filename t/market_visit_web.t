use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

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

    # Disable settlement, reset irritation to make counter deterministic
    $char = $t->app->characters->find(sub { 1 })->[0];
    my $act = $t->app->market->get($char->getCol('pending_activity_id'));
    $act->customer->{settle_chance} = 0;
    $act->customer->{irritation} = 0;
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
      ->json_like('/result' => qr/^sold/, 'result starts with sold')
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

subtest 'show — pressure state bands' => sub {
    my $t = setup;
    my $csrf = _csrf($t);

    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    my $char = $t->app->characters->find(sub { 1 })->[0];
    my $act = $t->app->market->get($char->getCol('pending_activity_id'));
    my $budget = $act->customer->{soft_budget} || 100;

    # Market.pm uses pct <= 0.50, <= 0.80, <= 1.00, <= 1.10, < 1.20, else
    # Compute spent values that safely land in each band for any budget >= 50
    my @bands = (
        { pct => 0.00, expected => 'mood_comfortable' },
        { pct => 0.50, expected => 'mood_comfortable' },
        { pct => 0.65, expected => 'mood_interested' },
        { pct => 0.80, expected => 'mood_interested' },
        { pct => 0.90, expected => 'mood_wary' },
        { pct => 1.00, expected => 'mood_wary' },
        { pct => 1.05, expected => 'mood_strained' },
        { pct => 1.10, expected => 'mood_strained' },
        { pct => 1.15, expected => 'mood_leaving' },
        { pct => 1.19, expected => 'mood_leaving' },
        { pct => 1.50, expected => 'mood_over_absolute' },
    );

    for my $band (@bands) {
        my $spent = int($budget * $band->{pct});
        $act->customer->{spent_so_far} = $spent;
        $act->save;

        my $pct_str = $budget ? sprintf('%.4f', $spent / $budget) : '0';
        $t->get_ok('/market' => {'Accept' => 'application/json'})
          ->status_is(200)
          ->json_is('/market_visit/pressure_state' => $band->{expected},
            "pressure_state=$band->{expected} (spent=$spent, budget=$budget, pct=$pct_str)");
    }
};

subtest 'negotiation fragment renders faction icon and portrait' => sub {
    my $t = setup;
    my $csrf = _csrf($t);

    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    my $char = $t->app->characters->find(sub { 1 })->[0];
    my $act = $t->app->market->get($char->getCol('pending_activity_id'));

    # Set irritation to get 'happy' portrait mood
    $act->customer->{irritation} = 0;
    $act->customer->{portrait_id} = 'port_001';
    $act->save;

    $t->get_ok('/market?_format=fragment')
      ->status_is(200)
      ->content_like(qr{src="/images/icon_\w+\.svg"}, 'faction icon URL')
      ->content_like(qr{data-reference-id="faction_\w+"}, 'faction reference link')
      ->content_like(qr{portraits/port_001_happy\.svg}, 'happy portrait URL');

    $act->customer->{irritation} = 2;
    $act->save;
    $t->get_ok('/market?_format=fragment')
      ->status_is(200)
      ->content_like(qr{portraits/port_001_neutral\.svg}, 'neutral portrait URL');

    $act->customer->{irritation} = 4;
    $act->save;
    $t->get_ok('/market?_format=fragment')
      ->status_is(200)
      ->content_like(qr{portraits/port_001_mad\.svg}, 'mad portrait URL');
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

subtest 'double send_away returns error on second call' => sub {
    my $t = setup;
    my $csrf = _csrf($t);

    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    $t->post_ok('/market/send_away' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/result' => 'sent_away');

    $t->post_ok('/market/send_away' => {'X-CSRF-Token' => $csrf})
      ->status_is(400)
      ->json_is('/ok' => 0)
      ->json_is('/error' => 'No active market visit');
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

    # Disable settlement, reset irritation to make mismatches deterministic
    $char = $t->app->characters->find(sub { 1 })->[0];
    my $act_id = $char->getCol('pending_activity_id');
    my $activity = $t->app->market->get($act_id);
    $activity->customer->{settle_chance} = 0;
    $activity->customer->{irritation} = 0;
    $activity->save;

    my $items = $t->app->shed->find(sub { $_[0]->{char_id} eq $char_id && $_[0]->{artifact_id} eq 'defense_item' });
    my $shed_item_id = $items->[0]->getCol('id');

    # 3 mismatches = irritation 3 (threshold is 4)
    for (1 .. 3) {
        $t->post_ok('/market/offer' => {'X-CSRF-Token' => $csrf},
            json => { shed_item_id => $shed_item_id })
          ->status_is(200)
          ->json_is('/result' => 'no_match');
    }

    # 4th mismatch → irritation hits 4 → customer_left
    $t->post_ok('/market/offer' => {'X-CSRF-Token' => $csrf},
        json => { shed_item_id => $shed_item_id })
      ->status_is(200)
      ->json_is('/result' => 'customer_left');

    my $char2 = $t->app->characters->find(sub { 1 })->[0];
    is($char2->getCol('pending_activity_id'), undef, 'activity cleared after customer_left');
};

done_testing;
