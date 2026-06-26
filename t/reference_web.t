use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib");

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

subtest 'unauthenticated returns 302' => sub {
    my $t = setup;
    $t->delete_ok('/sessions')->status_is(200);
    $t->get_ok('/reference/faction_syndicate')
      ->status_is(302)
      ->header_like(Location => qr{/login});
};

subtest 'unknown id returns 204' => sub {
    my $t = setup;
    $t->get_ok('/reference/nonexistent?_format=fragment')
      ->status_is(204);
};

subtest 'unknown id JSON returns 204' => sub {
    my $t = setup;
    $t->get_ok('/reference/nonexistent')
      ->status_is(204);
};

subtest 'fragment renders known entry' => sub {
    my $t = setup;
    $t->get_ok('/reference/faction_syndicate?_format=fragment')
      ->status_is(200)
      ->content_like(qr{SYND\.8TE}, 'title rendered')
      ->content_like(qr{Syndicate}, 'subtitle rendered')
      ->content_like(qr{/images/icon_syndicate\.svg}, 'icon URL rendered')
      ->content_like(qr{B\.L\.O\.T\.}, 'body text rendered');
};

subtest 'JSON endpoint returns entry' => sub {
    my $t = setup;
    $t->get_ok('/reference/faction_libremount', {'Accept' => 'application/json'})
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/entry/title' => 'LBR_MT.01')
      ->json_has('/entry/icon');
};

done_testing;
