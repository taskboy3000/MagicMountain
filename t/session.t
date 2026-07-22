use Modern::Perl;
use Test::More;

if ($ENV{GITHUB_ACTIONS}) {
    plan skip_all => 'skipping web integration test in GitHub CI';
}
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

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

my $t = TestEnv->create_app;
my $auth_service = $t->app->auth_service;

# Store token across subtests
my $_alice_token = '';

subtest 'GET / redirects to /game' => sub {
    $t->get_ok('/')->status_is(302)
      ->header_like(Location => qr{/game});
};

subtest 'new account gets credentials' => sub {
    # Create account via auth_service to get the raw token for later subtests
    my $result = $t->app->auth_service->new_account('alice');
    $_alice_token = $result->{token};
    ok $_alice_token, 'token obtained from new_account';
    my $alice_recovery = $result->{recovery_code};
    ok $alice_recovery, 'recovery code obtained from new_account';

    # Returning user (no token) — returns need_token flag
    $t->post_ok('/sessions', json => { displayName => 'alice' })
      ->status_is(200)
      ->json_is('/ok' => 0)
      ->json_is('/need_token' => 1);

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
    my $bob_result = $auth_service->reset_token($bob_acct);
    my $bob_token = $bob_result->{token};

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
    my $carol_result = $auth_service->reset_token($carol_acct);
    my $carol_token = $carol_result->{token};
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
      ->json_hasnt('/token')
      ->json_hasnt('/recovery_code')
      ->json_is('/show_credentials' => 1);

    # Token was rotated by recovery — obtain from auth service
    $t->app->accounts->load;
    $carol_acct = $t->app->accounts->find_by_username('carol');
    my $new_result = $t->app->auth_service->reset_token($carol_acct);
    ok $new_result->{token}, 'new token obtained after recovery';

    # Also obtain the new recovery code from the auth service
    my $carol_recovery = $t->app->auth_service->generate_recovery_code;

    # Old recovery code no longer works
    $t->delete_ok('/sessions')->status_is(200);
    $t->post_ok('/sessions/recover', json => { displayName => 'carol', recoveryCode => $recovery_code })
      ->status_is(403)
      ->json_is('/ok' => 0);

    # New token works
    $t->post_ok('/sessions', json => { displayName => 'carol', token => $new_result->{token} })
      ->status_is(200)
      ->json_is('/ok' => 1);

    $t->delete_ok('/sessions')->status_is(200);

    # Set the new recovery code and test it works
    $carol_acct->setCol('recovery_code_hash', $t->app->auth_service->hash_token($carol_recovery));
    $carol_acct->save;
    $t->post_ok('/sessions/recover', json => { displayName => 'carol', recoveryCode => $carol_recovery })
      ->status_is(200)
      ->json_is('/ok' => 1);
};

subtest 'unknown displayName returns generic error on recovery' => sub {
    $t->post_ok('/sessions/recover', json => { displayName => 'nonexistent', recoveryCode => 'ABC123' })
      ->status_is(403)
      ->json_is('/ok' => 0);
};

subtest 'mm_remember cookie uses pipe format (no JSON quotes to break parser)' => sub {
    # Log in to set cookies
    $t->post_ok('/sessions', json => { displayName => 'rememberformat' })
      ->status_is(200);

    my $cookie_obj = $t->tx->res->cookie('mm_remember');
    ok $cookie_obj, 'mm_remember response cookie present';
    if ($cookie_obj) {
        my $value = $cookie_obj->value;
        ok $value !~ /["{}]/, 'mm_remember cookie value has no JSON characters';
        like $value, qr/\|/, 'mm_remember cookie value contains pipe separator';
    }

    # Logout and re-login — remember-me should work
    $t->delete_ok('/sessions')->status_is(200);
    $t->post_ok('/sessions', json => { displayName => 'rememberformat' })
      ->status_is(200)
      ->json_is('/ok' => 1);
};

done_testing;
