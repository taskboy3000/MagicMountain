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

    return $dataDir;
}

sub add_shed_item {
    my ($dataDir, $char_id) = @_;
    my $shed = MagicMountain::Model::ShedItem->new(file => "$dataDir/shed.json");
    $shed->create(
        char_id => $char_id, artifact_id => 'test_cog',
        original_value => 10, decayed_value => 10,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => ['thermal'],
        estimated_value_min => 8, estimated_value_max => 12,
    )->save;
}

subtest 'JSON — shed + AP available shows suggestions' => sub {
    my $dataDir = setup;
    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    my $char = $chars->find(sub { 1 })->[0];
    add_shed_item($dataDir, $char->getCol('id'));

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);

    $t->get_ok('/home')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_has('/suggestions');

    my $suggestions = $t->tx->res->json->{suggestions};
    my @texts = map { $_->{text} } @$suggestions;

    ok grep(/Shed inventory detected/, @texts), 'shed_available advisory present';
    ok grep(/Mountain intake/, @texts), 'ap_available advisory present';
};

subtest 'JSON — no shed + no AP shows idle suggestion' => sub {
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

    $t->get_ok('/home')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_has('/suggestions');

    my $suggestions = $t->tx->res->json->{suggestions};
    my @texts = map { $_->{text} } @$suggestions;

    ok grep(/No salvage logged/, @texts), 'idle advisory present';
};

subtest 'JSON — shed + no AP shows no_ap_with_shed suggestion' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'stocked');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'stocked', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 0, action_points_max => 15,
    )->save;

    my $char = $chars->find(sub { 1 })->[0];
    add_shed_item($dataDir, $char->getCol('id'));

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'stocked' })->status_is(200);

    $t->get_ok('/home')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_has('/suggestions');

    my $suggestions = $t->tx->res->json->{suggestions};
    my @texts = map { $_->{text} } @$suggestions;

    ok grep(/in storage awaiting/, @texts), 'no_ap_with_shed advisory present';
};

subtest 'JSON — season end shows season_end suggestion' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 28, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'closer');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'closer', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
    )->save;

    my $char = $chars->find(sub { 1 })->[0];
    add_shed_item($dataDir, $char->getCol('id'));

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'closer' })->status_is(200);

    $t->get_ok('/home')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_has('/suggestions');

    my $suggestions = $t->tx->res->json->{suggestions};
    my @texts = map { $_->{text} } @$suggestions;

    ok grep(/Season terminal/, @texts), 'season_end advisory present';
};

subtest 'JSON — faction hunger suggestion appears when days_since_purchase >= 3' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 10, length => 30,
            faction_state => {
                syndicate => { name => 'Syndicate', days_since_purchase => 4 },
            })->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'hungry_faction');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'hungry_faction', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
    )->save;

    my $char = $chars->find(sub { 1 })->[0];
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
    $t->post_ok('/sessions', json => { displayName => 'hungry_faction' })->status_is(200);

    $t->get_ok('/home')
      ->status_is(200)
      ->json_is('/ok' => 1);

    my $suggestions = $t->tx->res->json->{suggestions};
    my @texts = map { $_->{text} } @$suggestions;

    # Should have shed_available, ap_available, AND faction_hunger
    ok grep(/Syndicate/, @texts), 'faction hunger advisory references Syndicate';
};

subtest 'fragment — renders dashboard with advisory text' => sub {
    my $dataDir = setup;
    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    my $char = $chars->find(sub { 1 })->[0];
    add_shed_item($dataDir, $char->getCol('id'));

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);

    $t->get_ok('/home?_format=fragment')
      ->status_is(200)
      ->content_like(qr/Shed inventory detected/, 'fragment contains shed_available advisory')
      ->content_like(qr/Mountain intake/, 'fragment contains ap_available advisory')
      ->content_like(qr/OFFER/, 'fragment contains offer suggestion icon')
      ->content_like(qr/DRILL/, 'fragment contains drill suggestion icon');
};

done_testing;
