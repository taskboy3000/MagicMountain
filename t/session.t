use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use Mojo::JSON qw(decode_json);

sub audit_entries {
    my ($file) = @_;
    return [] unless -e $file;
    open my $fh, '<', $file or die $!;
    my @entries;
    while (my $line = <$fh>) {
        chomp $line;
        next unless $line;
        push @entries, Mojo::JSON::decode_json($line);
    }
    close $fh;
    return \@entries;
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

subtest 'GET / redirects to /login when unauthenticated' => sub {
    $t->get_ok('/')->status_is(302)
      ->header_like(Location => qr{/login});
};

subtest 'session created on login' => sub {
    $t->post_ok('/sessions', json => { displayName => 'alice' })
      ->status_is(200)
      ->json_is('/ok' => 1);

    my $session = $t->app->session_store->find_by_player_id($aliceId);
    ok $session, 'session record exists after login';
    ok $session->getCol('last_active') > 0, 'last_active is set';

    my $entries = audit_entries("$dataDir/audit.jsonl");
    ok audit_has($entries, 'login', $aliceId), 'audit log has login event';
};

subtest 'GET / redirects to /game when authenticated' => sub {
    $t->get_ok('/')->status_is(302)
      ->header_like(Location => qr{/game});
};

subtest 'GET /player returns player when session valid' => sub {
    $t->get_ok('/player')
      ->status_is(200)
      ->json_is('/ok' => 1)
      ->json_is('/player/id' => $aliceId)
      ->json_is('/player/displayName' => 'alice');
};

subtest 'GET /game shows game page when authenticated' => sub {
    $t->get_ok('/game')
      ->status_is(200)
      ->content_like(qr/<!DOCTYPE html>/, 'layout template rendered')
      ->content_like(qr/id="player-name"/, 'player name element present')
      ->content_like(qr/id="season-info"/, 'season info element present');
};

subtest 'touch updates last_active' => sub {
    my $session_before = $t->app->session_store->find_by_player_id($aliceId);
    my $before = $session_before->getCol('last_active');

    $t->get_ok('/player')->status_is(200);

    $t->app->session_store->load;
    my $session_after = $t->app->session_store->find_by_player_id($aliceId);
    my $after = $session_after->getCol('last_active');
    cmp_ok $after, '>=', $before, 'last_active updated by touch on request';
};

subtest 'expired session redirects to login and cleans up' => sub {
    my $session = $t->app->session_store->find_by_player_id($aliceId);
    $session->setCol('last_active', time - 7200);
    $session->save;

    $t->get_ok('/player')
      ->status_is(302)
      ->header_like(Location => qr{/login});

    $t->app->session_store->load;
    my $gone = $t->app->session_store->find_by_player_id($aliceId);
    ok !$gone, 'expired session record deleted from store';
};

subtest 're-login after expiry creates new session' => sub {
    $t->post_ok('/sessions', json => { displayName => 'alice' })
      ->status_is(200)
      ->json_is('/ok' => 1);

    my $session = $t->app->session_store->find_by_player_id($aliceId);
    ok $session, 'new session record exists after re-login';
    cmp_ok $session->getCol('last_active'), '>', time - 10,
      'last_active is recent';

    $t->get_ok('/player')->status_is(200)->json_is('/ok' => 1);
};

subtest 'logout destroys session record' => sub {
    my $session = $t->app->session_store->find_by_player_id($aliceId);
    ok $session, 'session exists before logout';

    $t->delete_ok('/sessions')
      ->status_is(200)
      ->json_is('/ok' => 1);

    $t->app->session_store->load;
    my $gone = $t->app->session_store->find_by_player_id($aliceId);
    ok !$gone, 'session record deleted after logout';

    my $entries = audit_entries("$dataDir/audit.jsonl");
    ok audit_has($entries, 'logout', $aliceId), 'audit log has logout event';
};

subtest 'GET /game redirects to /login after logout' => sub {
    $t->get_ok('/game')->status_is(302)
      ->header_like(Location => qr{/login});
};

subtest 'GET /player redirects to /login after logout' => sub {
    $t->get_ok('/player')->status_is(302)
      ->header_like(Location => qr{/login});
};

subtest 'GET /player with no session redirects to /login' => sub {
    my $t2 = Test::Mojo->new('MagicMountain');
    $t2->get_ok('/player')->status_is(302)
       ->header_like(Location => qr{/login});
};

subtest 'GET /game with no session redirects to /login' => sub {
    my $t3 = Test::Mojo->new('MagicMountain');
    $t3->get_ok('/game')->status_is(302)
       ->header_like(Location => qr{/login});
};

subtest 'DELETE /player deletes account, character, and session' => sub {
    my $chars = MagicMountain::Model::Character->new(
        file => "$dataDir/characters.json",
    );
    my $char = $chars->create(
        name       => 'alice_char',
        account_id => $aliceId,
        season_id  => 's1',
        score      => 0,
    );
    $char->save;
    my $charId = $char->getCol('id');

    $t->post_ok('/sessions', json => { displayName => 'alice' })
      ->status_is(200)->json_is('/ok' => 1);

    $t->delete_ok('/player')
      ->status_is(200)
      ->json_is('/ok' => 1);

    $t->app->accounts->load;
    ok !$t->app->accounts->get($aliceId), 'account deleted';

    $t->app->session_store->load;
    ok !$t->app->session_store->find_by_player_id($aliceId),
      'session deleted';

    $chars->load;
    ok !$chars->get($charId), 'character deleted';

    my $entries = audit_entries("$dataDir/audit.jsonl");
    ok audit_has($entries, 'account_deleted', $aliceId),
      'audit log has account_deleted event';
};

subtest 'login rejected for disabled account' => sub {
    my $bob = $t->app->accounts->create(username => 'bob', disabled => 1);
    $bob->save;

    $t->post_ok('/sessions', json => { displayName => 'bob' })
      ->status_is(403)
      ->json_is('/ok' => 0)
      ->json_is('/error' => 'Account is disabled');
};

done_testing;
