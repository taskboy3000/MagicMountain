use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib");
$ENV{MOJO_MODE} = 'test';

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::Season;

sub setup_with_sales {
    my %sales = @_;
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;

    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(id => 's1', label => 'Test', status => 'active', day => 1, length => 30)->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'player');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    my $char = $chars->create(
        name => 'player', account_id => $a->getCol('id'), season_id => 's1',
        score => 0, scrap => 0, action_points => 15, action_points_max => 15,
    );
    $char->setCol('faction_sales', \%sales);
    $char->save;

    my $t = Test::Mojo->new('MagicMountain');
    $t->post_ok('/sessions', json => { displayName => 'player' })->status_is(200);
    return $t;
}

subtest 'top faction gets full stars, others proportional' => sub {
    my $t = setup_with_sales(syndicate => 10, libremount => 5, purifiers => 0);
    $t->get_ok('/factions?_format=fragment')->status_is(200);

    my $html = $t->tx->res->body;
    like $html, qr{The Syndicate}ms, 'syndicate rendered';
    like $html, qr{LibreMount}ms, 'libremount rendered';
    like $html, qr{★★★★★}ms, '5-star string present';
    like $html, qr{★★☆☆☆}ms, '2-star string present';
    like $html, qr{☆☆☆☆☆}ms, '0-star string present';
    my @five  = $html =~ /★★★★★/g;
    my @two   = $html =~ /★★☆☆☆/g;
    my @zero  = $html =~ /☆☆☆☆☆/g;
    is scalar(@five), 1, 'exactly one faction has 5 stars';
    is scalar(@two),  1, 'exactly one faction has 2 stars';
    is scalar(@zero), 3, 'three factions have 0 stars';
};

subtest 'all equal — all get full stars' => sub {
    my $t = setup_with_sales(syndicate => 7, libremount => 7);
    $t->get_ok('/factions?_format=fragment')->status_is(200);

    my $html = $t->tx->res->body;
    my @five = $html =~ /★★★★★/g;
    is scalar(@five), 2, 'two factions get 5 stars when tied';
};

subtest 'no sales — all zero stars' => sub {
    my $t = setup_with_sales(syndicate => 0, libremount => 0);
    $t->get_ok('/factions?_format=fragment')->status_is(200);

    my $html = $t->tx->res->body;
    my @zero = $html =~ /☆☆☆☆☆/g;
    is scalar(@zero), 5, 'all five factions get 0 stars';
};

done_testing;
