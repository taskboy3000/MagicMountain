use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

sub make_app {
    my ($cap) = @_;
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    my $t = Test::Mojo->new('MagicMountain');
    $t->app->config->{max_concurrent_sessions} = $cap;
    return $t;
}

# ----- Default cap of 10 -----
subtest 'default cap of 10 allows 10, blocks 11th' => sub {
    my $t = make_app(10);
    for my $i (1 .. 10) {
        $t->post_ok('/sessions', json => { displayName => "p$i" })
          ->status_is(200)->json_is('/ok' => 1);
        $t->ua->cookie_jar->empty;
    }
    $t->post_ok('/sessions', json => { displayName => 'extra' })
      ->status_is(503)->json_is('/ok' => 0);
};

# ----- Unlimited (cap = 0) -----
subtest 'cap = 0 allows unlimited sessions' => sub {
    my $t = make_app(0);
    for my $i (1 .. 15) {
        $t->post_ok('/sessions', json => { displayName => "u_$i" })
          ->status_is(200)->json_is('/ok' => 1);
        $t->ua->cookie_jar->empty;
    }
};

# ----- Cap of 1 -----
subtest 'cap = 1 blocks second player' => sub {
    my $t = make_app(1);
    $t->post_ok('/sessions', json => { displayName => 'first' })
      ->status_is(200)->json_is('/ok' => 1);
    $t->ua->cookie_jar->empty;
    $t->post_ok('/sessions', json => { displayName => 'second' })
      ->status_is(503)->json_is('/ok' => 0);
};

# ----- Same player reconnects at cap -----
subtest 'same player reconnecting bypasses cap' => sub {
    my $t = make_app(1);
    $t->post_ok('/sessions', json => { displayName => 'alice' })
      ->status_is(200)->json_is('/ok' => 1);
    # Reconnect with same cookie — uses existing session path
    $t->post_ok('/sessions', json => { displayName => 'alice' })
      ->status_is(200)->json_is('/ok' => 1);
    # Different player still blocked
    $t->ua->cookie_jar->empty;
    $t->post_ok('/sessions', json => { displayName => 'bob' })
      ->status_is(503)->json_is('/ok' => 0);
};

# ----- Expired session frees slot -----
subtest 'expired session does not count toward cap' => sub {
    my $t = make_app(1);
    $t->post_ok('/sessions', json => { displayName => 'alice' })
      ->status_is(200)->json_is('/ok' => 1);

    # Manually expire alice's session
    $t->app->session_store->load;
    my $sess = $t->app->session_store->find_by_player_id(
        $t->app->accounts->find_by_username('alice')->getCol('id')
    );
    $sess->setCol('last_active', time - 35 * 60);
    $sess->save;

    $t->ua->cookie_jar->empty;
    $t->post_ok('/sessions', json => { displayName => 'bob' })
      ->status_is(200)->json_is('/ok' => 1);
};

# ----- Error response shape -----
subtest 'cap error response has correct shape' => sub {
    my $t = make_app(1);
    $t->post_ok('/sessions', json => { displayName => 'first' })
      ->status_is(200);
    $t->ua->cookie_jar->empty;
    $t->post_ok('/sessions', json => { displayName => 'second' })
      ->status_is(503)
      ->json_is('/ok' => 0)
      ->json_is('/error' => 'Server at capacity. Try again later.');
};

done_testing;
