use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::Model::Account;
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
write_file("$dataDir/accounts.json", '{}');

my $account = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
my $alice = $account->create(username => 'alice');
$alice->save;
my $aliceId = $alice->getCol('id');

my $t = Test::Mojo->new('MagicMountain');

subtest 'GET / redirects to /login when unauthenticated' => sub {
    $t->get_ok('/')->status_is(302)
      ->header_like(Location => qr{/login});
};

subtest 'GET /login returns login form' => sub {
    $t->get_ok('/login')->status_is(200)
      ->content_like(qr/<!DOCTYPE html>/, 'layout template rendered')
      ->content_like(qr/Magic Mountain/);
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

done_testing;
