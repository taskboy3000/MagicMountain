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
use MagicMountain::Service::Authentication;

my $dataDir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $dataDir;

my $t = TestEnv->create_app;
my $auth_service = $t->app->auth_service;

subtest 'token-prompt fragment renders correctly' => sub {
    $t->get_ok('/sessions/token-prompt?display_name=alice&_format=fragment')
      ->status_is(200)
      ->content_like(qr/TOKEN REQUIRED/)
      ->content_like(qr/alice/)
      ->content_like(qr{action="\Q/sessions\E"})
      ->content_like(qr/data-display-name="alice"/)
      ->content_like(qr{id="forgot-token-link" data-fragment-url="\Q/sessions/recovery-form\E});

    # Missing display_name renders with empty
    $t->get_ok('/sessions/token-prompt?_format=fragment')
      ->status_is(200)
      ->content_like(qr/TOKEN REQUIRED/);

    # Missing _format returns JSON error
    $t->get_ok('/sessions/token-prompt?display_name=alice')
      ->status_is(400)
      ->json_is('/ok' => 0);
};

subtest 'recovery-form fragment renders correctly' => sub {
    $t->get_ok('/sessions/recovery-form?display_name=bob&_format=fragment')
      ->status_is(200)
      ->content_like(qr/RECOVER ACCOUNT/)
      ->content_like(qr/bob/)
      ->content_like(qr/an admin/)
      ->content_like(qr{action="\Q/sessions/recover\E"})
      ->content_like(qr/data-display-name="bob"/)
      ->content_like(qr{id="back-to-token-link" data-fragment-url="\Q/sessions/token-prompt\E});

    # Missing _format returns JSON error
    $t->get_ok('/sessions/recovery-form?display_name=bob')
      ->status_is(400)
      ->json_is('/ok' => 0);
};

subtest 'unauthenticated game page — login form data attributes' => sub {
    $t->get_ok('/game')
      ->status_is(200)
      ->content_like(qr/<body data-game-url="\/game"/)
      ->content_like(qr{<form id="login-form" action="\Q/sessions\E" data-game-url="\Q/game\E">});
};

subtest 'credentials fragment — new account flow' => sub {
    $t->post_ok('/sessions' => {'Accept' => 'application/json'} => json => { displayName => 'charlie' })
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/show_credentials' => 1);

    $t->get_ok('/sessions/credentials?_format=fragment')
      ->status_is(200)
      ->content_like(qr/CREDENTIALS/)
      ->content_like(qr/Write both down/)
      ->content_like(qr{id="continue-btn" data-game-url="\Q/game\E});

    # Second fetch returns 204 (one-time)
    $t->get_ok('/sessions/credentials?_format=fragment')
      ->status_is(204);

    # Missing _format returns JSON error
    $t->get_ok('/sessions/credentials')
      ->status_is(400)
      ->json_is('/ok' => 0);
};

subtest 'credentials fragment — recovery flow' => sub {
    my $acct = $t->app->accounts->create(username => 'dave');
    $acct->save;
    my $recovery_code = $auth_service->generate_recovery_code;
    $acct->setCol('recovery_code_hash', $auth_service->hash_token($recovery_code));
    $acct->save;

    $t->post_ok('/sessions/recover' => {'Accept' => 'application/json'} => json => { displayName => 'dave', recoveryCode => $recovery_code })
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/show_credentials' => 1);

    $t->get_ok('/sessions/credentials?_format=fragment')
      ->status_is(200)
      ->content_like(qr/CREDENTIALS/);
};

subtest 'credentials fragment — already consumed returns 204' => sub {
    $t->get_ok('/sessions/credentials?_format=fragment')
      ->status_is(204);
};

subtest 'unauthenticated game page — login form data attributes' => sub {
    $t->reset_session;
    $t->get_ok('/game')
      ->status_is(200)
      ->content_like(qr/<body data-game-url="\/game"/)
      ->content_like(qr{<form id="login-form" action="\Q/sessions\E" data-game-url="\Q/game\E">});
};

subtest 'full login flow — create, fetch credentials, use token' => sub {
    $t->reset_session;

    # Create account via POST (stores credentials in session)
    $t->post_ok('/sessions' => {'Accept' => 'application/json'} => json => { displayName => 'eve' })
      ->status_is(200)
      ->json_is('/ok' => 1);

    # Fetch credentials from session
    $t->get_ok('/sessions/credentials?_format=fragment')
      ->status_is(200)
      ->content_like(qr/CREDENTIALS/);

    # Eve is already logged in from the POST — redirect to game
    $t->get_ok('/game')
      ->status_is(200)
      ->content_like(qr/REGISTERED TO/)
      ->content_like(qr{data-game-url="\Q/game\E"})
      ->content_like(qr{data-nav-url="\Q/nav\E"})
      ->content_like(qr{data-season-recap-url="\Q/season/recap\E})
      ->content_like(qr{data-orientation-url="\Q/orientation\E})
      ->content_like(qr{data-onboarding-url="\Q/onboarding/notice\E});
};

done_testing;
