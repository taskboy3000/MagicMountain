use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::AuditLog;
use MagicMountain::Service::Authentication;

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

my $t = Test::Mojo->new('MagicMountain');
my $auth_service = $t->app->auth_service;

# Store token across subtests
my $_alice_token = '';

subtest 'GET / redirects to /game' => sub {
    $t->get_ok('/')->status_is(302)
      ->header_like(Location => qr{/game});
};

subtest 'new account gets credentials' => sub {
    $t->post_ok('/sessions', json => { displayName => 'alice' })
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_has('/token')
      ->json_has('/recovery_code')
      ->json_is('/show_credentials' => 1);

    $_alice_token = $t->tx->res->json->{token};
    ok $_alice_token, 'token received';
    my $alice_recovery = $t->tx->res->json->{recovery_code};
    ok $alice_recovery, 'recovery code received';

    my $account = $t->app->accounts->find_by_username('alice');
    ok $account, 'account created';
    ok $account->getCol('token_hash'), 'token_hash set';
    ok $account->getCol('recovery_code_hash'), 'recovery_code_hash set';
    is $account->getCol('banned'), 0, 'banned is 0';
};

subtest 'returning with correct token succeeds' => sub {
    ok $_alice_token, 'have token from previous test';

    $t->post_ok('/sessions', json => { displayName => 'alice', token => $_alice_token })
      ->status_is(200)
      ->json_is('/ok' => 1);

    my $player_id = $t->tx->res->json->{player}{id};
    my $session = $t->app->session_store->find_by_player_id($player_id);
    ok $session, 'session created';

    my $entries = audit_entries("$dataDir/audit.jsonl");
    ok audit_has($entries, 'login', $player_id), 'audit log has login event';
};

subtest 'wrong token fails' => sub {
    $t->delete_ok('/sessions')->status_is(200);
    $t->post_ok('/sessions', json => { displayName => 'alice', token => 'wrong-token-here' })
      ->status_is(403)
      ->json_is('/ok' => 0);
};

subtest 'touch updates last_active' => sub {
    $t->post_ok('/sessions', json => { displayName => 'alice', token => $_alice_token })
      ->status_is(200)->json_is('/ok' => 1);
    my $player_id = $t->tx->res->json->{player}{id};

    my $session_before = $t->app->session_store->find_by_player_id($player_id);
    my $before = $session_before->getCol('last_active');

    $t->get_ok('/player')->status_is(200);

    $t->app->session_store->load;
    my $session_after = $t->app->session_store->find_by_player_id($player_id);
    my $after = $session_after->getCol('last_active');
    cmp_ok $after, '>=', $before, 'last_active updated by touch on request';
};

subtest 'expired session redirects to login' => sub {
    $t->post_ok('/sessions', json => { displayName => 'alice', token => $_alice_token })
      ->status_is(200)->json_is('/ok' => 1);
    my $player_id = $t->tx->res->json->{player}{id};

    my $session = $t->app->session_store->find_by_player_id($player_id);
    $session->setCol('last_active', time - 7200);
    $session->save;

    $t->get_ok('/player')
      ->status_is(302)
      ->header_like(Location => qr{/login});

    $t->app->session_store->load;
    my $gone = $t->app->session_store->find_by_player_id($player_id);
    ok !$gone, 'expired session record deleted from store';
};

subtest 'logout destroys session record' => sub {
    $t->post_ok('/sessions', json => { displayName => 'alice', token => $_alice_token })
      ->status_is(200)->json_is('/ok' => 1);
    my $player_id = $t->tx->res->json->{player}{id};

    my $session = $t->app->session_store->find_by_player_id($player_id);
    ok $session, 'session exists before logout';

    $t->delete_ok('/sessions')
      ->status_is(200)
      ->json_is('/ok' => 1);

    $t->app->session_store->load;
    my $gone = $t->app->session_store->find_by_player_id($player_id);
    ok !$gone, 'session record deleted after logout';

    my $entries = audit_entries("$dataDir/audit.jsonl");
    ok audit_has($entries, 'logout', $player_id), 'audit log has logout event';
};

subtest 'GET /game shows login form after logout' => sub {
    $t->get_ok('/game')->status_is(200)
      ->content_like(qr/PROSPECTBOY 3000 REGISTRATION/);
};

subtest 'login rejected for banned account' => sub {
    $t->delete_ok('/sessions')->status_is(200);

    my $bob_acct = $t->app->accounts->create(username => 'bob');
    $bob_acct->save;
    my $bob_token = $auth_service->reset_token($bob_acct);

    $t->post_ok('/sessions', json => { displayName => 'bob', token => $bob_token })
      ->status_is(200)->json_is('/ok' => 1);

    $t->delete_ok('/sessions')->status_is(200);

    $t->app->accounts->load;
    my $bob = $t->app->accounts->find_by_username('bob');
    $bob->setCol('banned', 1);
    $bob->save;

    $t->post_ok('/sessions', json => { displayName => 'bob', token => $bob_token })
      ->status_is(403)
      ->json_is('/ok' => 0)
      ->json_is('/error' => 'Account banned');
};

subtest 'recovery code works and rotates credentials' => sub {
    $t->delete_ok('/sessions')->status_is(200);

    my $carol_acct = $t->app->accounts->create(username => 'carol');
    $carol_acct->save;
    my $carol_token = $auth_service->reset_token($carol_acct);
    my $recovery_code = $auth_service->generate_recovery_code;
    my $recovery_hash = $auth_service->hash_token($recovery_code);
    $carol_acct->setCol('recovery_code_hash', $recovery_hash);
    $carol_acct->save;

    # Wrong recovery code fails
    $t->post_ok('/sessions/recover', json => { displayName => 'carol', recoveryCode => 'XXXXXX' })
      ->status_is(403)
      ->json_is('/ok' => 0);

    # Correct recovery code succeeds
    $t->post_ok('/sessions/recover', json => { displayName => 'carol', recoveryCode => $recovery_code })
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_has('/token')
      ->json_has('/recovery_code')
      ->json_is('/show_credentials' => 1);

    my $new_token = $t->tx->res->json->{token};
    my $new_recovery = $t->tx->res->json->{recovery_code};
    ok $new_token, 'new token received after recovery';
    ok $new_recovery, 'new recovery code received after recovery';

    # Old recovery code no longer works
    $t->delete_ok('/sessions')->status_is(200);
    $t->post_ok('/sessions/recover', json => { displayName => 'carol', recoveryCode => $recovery_code })
      ->status_is(403)
      ->json_is('/ok' => 0);

    # New token works
    $t->post_ok('/sessions', json => { displayName => 'carol', token => $new_token })
      ->status_is(200)
      ->json_is('/ok' => 1);

    $t->delete_ok('/sessions')->status_is(200);

    # New recovery code also works
    $t->post_ok('/sessions/recover', json => { displayName => 'carol', recoveryCode => $new_recovery })
      ->status_is(200)
      ->json_is('/ok' => 1);
};

subtest 'unknown displayName returns generic error on recovery' => sub {
    $t->post_ok('/sessions/recover', json => { displayName => 'nonexistent', recoveryCode => 'ABC123' })
      ->status_is(403)
      ->json_is('/ok' => 0);
};

done_testing;
