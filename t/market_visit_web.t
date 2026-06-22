use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
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

    # Get the shed_item_id from the character's shed
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

done_testing;
