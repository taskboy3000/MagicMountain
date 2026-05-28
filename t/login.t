use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::Model::Account;

my $dataDir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $dataDir;
write_file("$dataDir/accounts.json", '{}');

my $account = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
my $alice = $account->create(username => 'alice');
$alice->save;
my $aliceId = $alice->getCol('id');

my $t = Test::Mojo->new('MagicMountain');

subtest 'GET / returns login form' => sub {
    $t->get_ok('/')->status_is(200)->content_like(qr/Magic Mountain/);
};

subtest 'POST /api/sessions with valid name' => sub {
    $t->post_ok('/api/sessions', json => { displayName => 'alice' })
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/player/displayName' => 'alice')
      ->json_has('/player/id');
};

subtest 'POST /api/sessions with unknown name' => sub {
    $t->post_ok('/api/sessions', json => { displayName => 'nobody' })
      ->status_is(400)
      ->json_is('/ok' => 0)
      ->json_is('/error' => 'Account not found');
};

subtest 'POST /api/sessions without displayName' => sub {
    $t->post_ok('/api/sessions', json => {})
      ->status_is(400)
      ->json_is('/ok' => 0)
      ->json_is('/error' => 'displayName is required');
};

subtest 'DELETE /api/sessions logs out' => sub {
    $t->delete_ok('/api/sessions')
      ->status_is(200)
      ->json_is('/ok' => 1);
};

done_testing;
