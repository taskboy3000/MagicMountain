use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Model::Account;
use MagicMountain::Service::Authentication;

my $dataDir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $dataDir;

my $t = Test::Mojo->new('MagicMountain');
my $auth_service = $t->app->auth_service;

subtest 'token-prompt fragment renders correctly' => sub {
    $t->get_ok('/sessions/token-prompt?display_name=alice&_format=fragment')
      ->status_is(200)
      ->content_like(qr/TOKEN REQUIRED/)
      ->content_like(qr/alice/);

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
      ->content_like(qr/an admin/);

    # Missing _format returns JSON error
    $t->get_ok('/sessions/recovery-form?display_name=bob')
      ->status_is(400)
      ->json_is('/ok' => 0);
};

subtest 'credentials fragment — new account flow' => sub {
    $t->post_ok('/sessions', json => { displayName => 'charlie' })
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/show_credentials' => 1);

    $t->get_ok('/sessions/credentials?_format=fragment')
      ->status_is(200)
      ->content_like(qr/CREDENTIALS/)
      ->content_like(qr/Write both down/);

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

    $t->post_ok('/sessions/recover', json => { displayName => 'dave', recoveryCode => $recovery_code })
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/show_credentials' => 1);

    $t->get_ok('/sessions/credentials?_format=fragment')
      ->status_is(200)
      ->content_like(qr/CREDENTIALS/);
};

subtest 'credentials fragment — not logged in returns 204' => sub {
    $t->get_ok('/sessions/credentials?_format=fragment')
      ->status_is(204);
};

subtest 'full login flow — create, fetch credentials, use token' => sub {
    # Create account via POST (stores credentials in session)
    $t->post_ok('/sessions', json => { displayName => 'eve' })
      ->status_is(200)
      ->json_is('/ok' => 1);

    # Fetch credentials from session
    $t->get_ok('/sessions/credentials?_format=fragment')
      ->status_is(200)
      ->content_like(qr/CREDENTIALS/);

    # Eve is already logged in from the POST — redirect to game
    $t->get_ok('/game')
      ->status_is(200)
      ->content_like(qr/REGISTERED TO/);
};

done_testing;
