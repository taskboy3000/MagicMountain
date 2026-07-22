use Modern::Perl;

use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use Test::More;

if ($ENV{GITHUB_ACTIONS}) {
    plan skip_all => 'skipping web integration test in GitHub CI';
}
use Test::Mojo;
use File::Temp qw(tempdir);

my $dataDir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $dataDir;

my $t = TestEnv->create_app;

$t->app->config->{bots}{count} = 0;
$t->app->config->{pvp_enabled} = 1;

# Create season
$t->app->seasons->load;
my $s = $t->app->active_season;
if (!$s) {
    $s = $t->app->seasons->create(
        label => 'Test Season', length => 30, day => 1,
        end_of_day_hour => 0, status => 'active',
    );
    $s->save;
}

# Create rival account and character directly (will exist before player
# logs in, so the player will have a rival on their first /game visit).
$t->app->accounts->load;
$t->app->characters->load;

my $rival_acct = $t->app->accounts->create(username => 'rivalbot');
$rival_acct->save;

my $rival_char = $t->app->characters->create(
    name          => 'rivalbot',
    account_id    => $rival_acct->getCol('id'),
    season_id     => $s->getCol('id'),
    score         => 200,
    scrap         => 500,
    faction_sales => { syndicate => 1 },
);
$rival_char->save;

# Log in as player1 (new account, auto-created, gets cookie).
$t->post_ok('/sessions', json => { displayName => 'player1' })->status_is(200);

# Actually create the player1 character by visiting /game
$t->get_ok('/game')->status_is(200);

# Now update the character with the right score and faction_sales.
$t->app->characters->load;
my ($pc) = @{ $t->app->characters->find(sub { $_[0]->{name} eq 'player1' }) };
die "no player1 character" unless $pc;
$pc->setCol('score', 100);
$pc->setCol('faction_sales', { syndicate => 1 });
$pc->save;

subtest 'GET /pvp as fragment returns 200' => sub {
    $t->get_ok('/pvp?_format=fragment')->status_is(200);
};

subtest 'GET /pvp JSON includes rivals' => sub {
    $t->get_ok('/pvp')->status_is(200);
    $t->json_has('/rivals');
    $t->json_is('/rivals/0/name' => 'rivalbot');
    $t->json_has('/actions');
};

done_testing;
