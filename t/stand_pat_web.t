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

    my $shed = MagicMountain::Model::ShedItem->new(file => "$dataDir/shed.json");
    $shed->create(
        char_id => $char_id, artifact_id => 'defense_item',
        original_value => 20, decayed_value => 20,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => ['defense'],
        estimated_value_min => 16, estimated_value_max => 24,
    )->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

sub _csrf { my $t = shift; $t->tx->res->json->{csrf_token} // '' }

subtest 'stand_pat with high skill — sale goes through' => sub {
    my $t = setup;
    my $csrf = _csrf($t);

    my $char = $t->app->characters->find(sub { 1 })->[0];
    my $char_id = $char->getCol('id');

    # High selling skill biases stand_pat toward success (30% + 45% = 75%)
    $char->setCol('skill_selling', 3);
    $char->save;

    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    $char = $t->app->characters->find(sub { 1 })->[0];
    my $act = $t->app->market->get($char->getCol('pending_activity_id'));
    $act->customer->{settle_chance} = 0;
    $act->save;

    my $items = $t->app->shed->find(sub { $_[0]->{char_id} eq $char_id && $_[0]->{artifact_id} eq 'defense_item' });
    my $shed_item_id = $items->[0]->getCol('id');

    $t->post_ok('/market/offer' => {'X-CSRF-Token' => $csrf}, json => { shed_item_id => $shed_item_id })
      ->status_is(200)
      ->json_is('/result' => 'counter_offer');

    $t->post_ok('/market/stand_pat' => {'X-CSRF-Token' => $csrf})
      ->status_is(200);

    my $result = $t->tx->res->json->{result};
    ok($result && $result ne 'counter_offer', "stand_pat with high skill resolved: $result")
      or diag explain $t->tx->res->json;
};

subtest 'stand_pat refused — irritation increases, counter persists' => sub {
    my $t = setup;
    my $csrf = _csrf($t);

    my $char = $t->app->characters->find(sub { 1 })->[0];
    my $char_id = $char->getCol('id');

    $t->post_ok('/market/begin' => {'X-CSRF-Token' => $csrf})->status_is(200);

    $char = $t->app->characters->find(sub { 1 })->[0];
    my $act = $t->app->market->get($char->getCol('pending_activity_id'));
    $act->customer->{settle_chance} = 0;
    $act->customer->{irritation} = 0;
    $act->save;

    my $items = $t->app->shed->find(sub { $_[0]->{char_id} eq $char_id && $_[0]->{artifact_id} eq 'defense_item' });
    my $shed_item_id = $items->[0]->getCol('id');

    $t->post_ok('/market/offer' => {'X-CSRF-Token' => $csrf}, json => { shed_item_id => $shed_item_id })
      ->status_is(200)
      ->json_is('/result' => 'counter_offer');

    # Force rand to low value so stand_pat fails
    srand(0);

    $t->post_ok('/market/stand_pat' => {'X-CSRF-Token' => $csrf})
      ->status_is(200)
      ->json_is('/result' => 'stand_pat_refused')
      ->json_is('/irritation' => 1.5)
      ->json_has('/message');

    # Counter should still be available
    my $char2 = $t->app->characters->find(sub { 1 })->[0];
    my $act2 = $t->app->market->get($char2->getCol('pending_activity_id'));
    ok($act2->customer->{pending_counter}, 'counter still available after refused stand_pat');
};

done_testing;
