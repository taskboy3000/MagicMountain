use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Model::Account;
use MagicMountain::Model::AuditLog;

sub audit_entries {
    my ($file) = @_;
    return MagicMountain::Model::AuditLog->new(file => $file)->all_entries;
}

sub audit_has {
    my ($entries, $event, $player_id) = @_;
    for my $e (@$entries) {
        if ($e->{event} eq $event
            && (!$player_id || ($e->{player_id} // '') eq $player_id)) {
            return 1;
        }
    }
    return 0;
}

my $dataDir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $dataDir;

my $account = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
my $alice = $account->create(username => 'alice');
$alice->save;
my $aliceId = $alice->getCol('id');

my $t = Test::Mojo->new('MagicMountain');

subtest 'GET / redirects to /game (login page is at /game now)' => sub {
    $t->get_ok('/')->status_is(302)
      ->header_like(Location => qr{/game});
};

subtest 'GET /login redirects to /game' => sub {
    $t->get_ok('/login')->status_is(302)
      ->header_like(Location => qr{/game});
};

subtest 'POST /sessions with valid name' => sub {
    $t->post_ok('/sessions', json => { displayName => 'alice' })
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/player/displayName' => 'alice')
      ->json_has('/player/id');
};

subtest 'POST /sessions with unknown name auto-creates account' => sub {
    $t->post_ok('/sessions', json => { displayName => 'bob' })
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/player/displayName' => 'bob')
      ->json_has('/player/id');

    my $bob = $t->app->accounts->find_by_username('bob');
    ok $bob, 'auto-created account exists in store';
    is $bob->getCol('username'), 'bob', 'auto-created account has correct username';

    my $entries = audit_entries("$dataDir/audit.jsonl");
    ok audit_has($entries, 'account_created', $bob->getCol('id')),
      'audit log has account_created event';
    ok audit_has($entries, 'login', $bob->getCol('id')),
      'audit log has login event for auto-created account';
};

subtest 'banned account rejected' => sub {
    my $data_dir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $data_dir;
    my $accts = MagicMountain::Model::Account->new(file => "$data_dir/accounts.json");
    $accts->create(id => 'a1', username => 'locked', banned => 1)->save;
    my $t2 = Test::Mojo->new('MagicMountain');
    $t2->post_ok('/sessions', json => { displayName => 'locked' })
      ->status_is(403)
      ->json_is('/error' => 'Account banned');
};

subtest 'POST /sessions without displayName' => sub {
    $t->post_ok('/sessions', json => {})
      ->status_is(400)
      ->json_is('/ok' => 0)
      ->json_is('/error' => 'displayName is required');
};

subtest 'DELETE /sessions logs out' => sub {
    $t->delete_ok('/sessions')
      ->status_is(200)
      ->json_is('/ok' => 1);
};

subtest 'existing session touched on re-login' => sub {
    my $t2 = Test::Mojo->new('MagicMountain');
    $t2->post_ok('/sessions', json => { displayName => 'alice' })
      ->status_is(200)
      ->json_is('/ok' => 1);
};

subtest 'logout redirects to login form' => sub {
    my $dataDir2 = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir2;
    my $t2 = Test::Mojo->new('MagicMountain');
    $t2->post_ok('/sessions', json => { displayName => 'alice' })->status_is(200);
    $t2->get_ok('/logout')
      ->status_is(302)
      ->header_like(Location => qr{/game});
};

done_testing;
