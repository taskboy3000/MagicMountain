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

sub setup_player {
    my ($dataDir, $attrs) = @_;
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active',
            day => $attrs->{day} // 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'tester'); $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->create(
        name => 'tester', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => $attrs->{scrap} // 0,
        action_points => $attrs->{ap} // 15, action_points_max => 15,
    )->save;

    return $a;
}

sub add_shed_item {
    my ($dataDir, $char_id, $behaviors) = @_;
    my $shed = MagicMountain::Model::ShedItem->new(file => "$dataDir/shed.json");
    $shed->create(
        char_id => $char_id, artifact_id => 'test_cog',
        original_value => 10, decayed_value => 10,
        condition => 'fresh', days_in_shed => 0,
        instability => 0, stage => 'stable', push_count => 0,
        has_evolved => 0, behaviors => $behaviors,
        estimated_value_min => 8, estimated_value_max => 12,
    )->save;
}

sub set_climate {
    my ($dataDir, $climate) = @_;
    my $season = MagicMountain::Model::Season->new(file => "$dataDir/seasons.json");
    $season->load;
    my $s = $season->find(sub { 1 })->[0];
    $s->setCol('faction_climate', $climate);
    $s->save;
}

subtest 'climate_finds — appears when has_meaningful_finds and AP available' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    my $a = setup_player($dataDir, { ap => 15 });
    set_climate($dataDir, {
        dominant_faction_name => 'Syndicate', intensity_label => 'Strong',
        intensity => 1, finds_summary => 'Strong boost: thermal.',
        has_meaningful_finds => 1,
        market => { market_summary => 'Neutral' },
    });

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'tester' })->status_is(200);
    $t->get_ok('/home')->status_is(200);
    my $suggestions = $t->tx->res->json->{suggestions};
    my @texts = map { $_->{text} } @$suggestions;
    ok grep(/Mountain favoring/, @texts), 'climate_finds advisory present';
    ok grep(/Strong boost: thermal/, @texts), 'finds_summary data in text';
};

subtest 'climate_finds — absent when has_meaningful_finds is false' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    my $a = setup_player($dataDir, { ap => 15 });
    set_climate($dataDir, {
        dominant_faction_name => 'Syndicate', intensity_label => 'Contested',
        intensity => 0, finds_summary => 'No meaningful climate effect on prospecting today.',
        has_meaningful_finds => 0,
        market => { market_summary => 'Neutral' },
    });

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'tester' })->status_is(200);
    $t->get_ok('/home')->status_is(200);
    my $suggestions = $t->tx->res->json->{suggestions};
    my @texts = map { $_->{text} } @$suggestions;
    ok !grep(/Mountain favoring/, @texts), 'climate_finds absent when no meaningful finds';
};

subtest 'climate_finds — absent when AP insufficient' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    my $a = setup_player($dataDir, { ap => 0 });
    set_climate($dataDir, {
        dominant_faction_name => 'Syndicate', intensity_label => 'Strong',
        intensity => 1, finds_summary => 'Strong boost: thermal.',
        has_meaningful_finds => 1,
        market => { market_summary => 'Neutral' },
    });

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'tester' })->status_is(200);
    $t->get_ok('/home')->status_is(200);
    my $suggestions = $t->tx->res->json->{suggestions};
    my @texts = map { $_->{text} } @$suggestions;
    ok !grep(/Mountain favoring/, @texts), 'climate_finds absent when no AP';
};

subtest 'banned_trait — appears when shed items have banned behaviors' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    my $a = setup_player($dataDir, { ap => 15, scrap => 10 });
    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->load;
    my $char = $chars->find(sub { 1 })->[0];
    add_shed_item($dataDir, $char->getCol('id'), ['thermal']);

    set_climate($dataDir, {
        dominant_faction_name => 'Syndicate', intensity_label => 'Strong',
        intensity => 1, banned_traits => ['thermal', 'storage'],
        market => { market_summary => 'Neutral' },
    });

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'tester' })->status_is(200);
    $t->get_ok('/home')->status_is(200);
    my $suggestions = $t->tx->res->json->{suggestions};
    my @texts = map { $_->{text} } @$suggestions;
    ok grep(/Restricted items in shed/, @texts), 'banned_trait advisory present';
    ok grep(/thermal/, @texts), 'banned trait name in advisory';
};

subtest 'banned_trait — absent when no banned traits match' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    my $a = setup_player($dataDir, { ap => 15, scrap => 10 });
    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    $chars->load;
    my $char = $chars->find(sub { 1 })->[0];
    add_shed_item($dataDir, $char->getCol('id'), ['force']);

    set_climate($dataDir, {
        dominant_faction_name => 'Syndicate', intensity_label => 'Strong',
        intensity => 1, banned_traits => ['thermal'],
        market => { market_summary => 'Neutral' },
    });

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'tester' })->status_is(200);
    $t->get_ok('/home')->status_is(200);
    my $suggestions = $t->tx->res->json->{suggestions};
    my @texts = map { $_->{text} } @$suggestions;
    ok !grep(/Restricted items in shed/, @texts), 'banned_trait absent when no match';
};

subtest 'scrap_low — appears when scrap < 5' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    my $a = setup_player($dataDir, { ap => 15, scrap => 3 });

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'tester' })->status_is(200);
    $t->get_ok('/home')->status_is(200);
    my $suggestions = $t->tx->res->json->{suggestions};
    my @texts = map { $_->{text} } @$suggestions;
    ok grep(/Scrap reserves low/, @texts), 'scrap_low advisory present';
};

subtest 'scrap_low — absent when scrap >= 5' => sub {
    my $dataDir = tempdir(CLEANUP => 1);
    my $a = setup_player($dataDir, { ap => 15, scrap => 5 });

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'tester' })->status_is(200);
    $t->get_ok('/home')->status_is(200);
    my $suggestions = $t->tx->res->json->{suggestions};
    my @texts = map { $_->{text} } @$suggestions;
    ok !grep(/Scrap reserves low/, @texts), 'scrap_low absent at scrap >= 5';
};

done_testing;
