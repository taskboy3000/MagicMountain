use Modern::Perl;

use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use YAML::XS qw(DumpFile);

my $dataDir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $dataDir;

my $t = TestEnv->create_app;

$t->app->config->{bots}{count} = 0;   # no bots
$t->app->config->{pvp_enabled} = 1;

# Disable the recurring maintenance timer so it doesn't fire mid-test.
# Already gated by mode eq 'test' in startup.

# ── Helper: create an account + character in the active season ──

sub _create_player {
    my ($name, $score) = @_;
    $score //= 0;
    my $a = $t->app->accounts->create(username => $name);
    $a->save;
    $t->app->seasons->load;
    $t->app->characters->load;
    my $s = $t->app->active_season;
    if (!$s) {
        # create one
        $s = $t->app->seasons->create(
            label => 'Test Season', length => 30, day => 1,
            end_of_day_hour => 0, status => 'active',
        );
        $s->save;
    }
    my $c = $t->app->characters->create(
        name        => $name,
        account_id  => $a->getCol('id'),
        season_id   => $s->getCol('id'),
        score       => $score,
        scrap       => 500,
        faction_sales => { syndicate => 1 },
    );
    $c->save;
    return ($a, $c, $s);
}

my ($attacker_acct, $attacker, $season) = _create_player('attacker', 100);
my ($target_acct,  $target)              = _create_player('target', 200);
my ($bottom_acct,  $bottom)              = _create_player('bottom', 50);
my $pvp = $t->app->pvp_service;
my $pressures = $t->app->pressures;

# ── Helpers ──────────────────────────────────────────────────────────

sub _reload_all {
    $t->app->characters->load;
    $t->app->pressures->load;
    $t->app->seasons->load;
}

# ── Tests ────────────────────────────────────────────────────────────

subtest 'apply_pressure validates effect_type' => sub {
    my $result = $pvp->apply_pressure($attacker, $target->getCol('id'), 'syndicate', 'fake_type');
    is($result->{ok}, 0, 'ok=0 for unknown effect_type');
    like($result->{error}, qr/unknown effect type/, 'error explains why');
};

subtest 'cannot press yourself' => sub {
    my $result = $pvp->apply_pressure($attacker, $attacker->getCol('id'), 'syndicate', 'corner_market');
    is($result->{ok}, 0);
    like($result->{error}, qr/cannot press yourself/);
};

subtest 'target not found' => sub {
    my $result = $pvp->apply_pressure($attacker, 'no-such-id', 'syndicate', 'corner_market');
    is($result->{ok}, 0);
    like($result->{error}, qr/target not found/);
};

subtest 'target not in same season' => sub {
    $t->app->characters->load;
    my $target2 = $t->app->characters->create(
        name => 'outsider', account_id => $target_acct->getCol('id'),
        season_id => 'other-season', score => 200, scrap => 500,
    );
    $target2->save;
    my $result = $pvp->apply_pressure($attacker, $target2->getCol('id'), 'syndicate', 'corner_market');
    is($result->{ok}, 0);
    like($result->{error}, qr/not in same season/);
};

subtest 'can only press rivals ranked above you' => sub {
    # Bottom (rank 3) CAN press attacker (rank 2) — attacker is ABOVE.
    my $result = $pvp->apply_pressure($bottom, $attacker->getCol('id'), 'syndicate', 'corner_market');
    is($result->{ok}, 1, 'bottom CAN press attacker ranked above');

    # Bottom (rank 3) CANNOT press target (rank 1) — already pressing? No, wrong.
    # Actually bottom CAN press anyone ranked above. What they can't do is press
    # someone ranked BELOW them. There's no one below bottom since we only have 3 chars,
    # so let's verify bottom CAN press target (rank 1).
    my $result2 = $pvp->apply_pressure($bottom, $target->getCol('id'), 'syndicate', 'corner_market');
    is($result2->{ok}, 1, 'bottom CAN press target (rank 1, above)');

    # Attacker (rank 2) CANNOT press bottom (rank 3) — bottom is BELOW.
    my $result3 = $pvp->apply_pressure($attacker, $bottom->getCol('id'), 'syndicate', 'corner_market');
    is($result3->{ok}, 0, 'attacker CANNOT press bottom ranked below');
    like($result3->{error}, qr/can only press rivals ranked above/);

    # Clean up the two succeeded pressure rows
    _reload_all;
    for (values %{ $pressures->table }) {
        $pressures->delete($_->{id});
    }
    _reload_all;
};

subtest 'target has no faction lead' => sub {
    my $result = $pvp->apply_pressure($attacker, $target->getCol('id'), 'nonexistent_faction', 'corner_market');
    is($result->{ok}, 0);
    like($result->{error}, qr/no lead with that faction/);
};

subtest 'pvp disabled' => sub {
    local $t->app->config->{pvp_enabled} = 0;
    my $result = $pvp->apply_pressure($attacker, $target->getCol('id'), 'syndicate', 'corner_market');
    is($result->{ok}, 0);
    like($result->{error}, qr/pvp disabled/);
};

subtest 'not enough scrap' => sub {
    $t->app->characters->load;
    my ($char) = @{ $t->app->characters->find(
        sub { $_[0]->{name} eq 'attacker' }
    ) };
    $char->setCol('scrap', 0);
    $char->save;
    my $result = $pvp->apply_pressure($char, $target->getCol('id'), 'syndicate', 'corner_market');
    is($result->{ok}, 0);
    like($result->{error}, qr/not enough scrap/);
    $char->setCol('scrap', 500);
    $char->save;
};

subtest 'pressure stack limit' => sub {
    # Fill the stack to max
    my $max = $t->app->config->{pvp_max_stack} // 3;
    for (1 .. $max) {
        $pressures->create(
            attacker_id => $attacker->getCol('id'),
            target_id   => $target->getCol('id'),
            faction_id  => 'syndicate',
            effect_type => 'corner_market',
        )->save;
    }
    _reload_all;
    my $n = $pvp->apply_pressure($attacker, $target->getCol('id'), 'syndicate', 'corner_market');
    is($n->{ok}, 0);
    like($n->{error}, qr/stack limit/);
    # Clean up
    for (values %{ $pressures->table }) {
        $pressures->delete($_->{id});
    }
    _reload_all;
};

subtest 'happy path: corner_market' => sub {
    _reload_all;
    my $scrap_before = $attacker->getCol('scrap') // 0;
    my $result = $pvp->apply_pressure($attacker, $target->getCol('id'), 'syndicate', 'corner_market');
    is($result->{ok}, 1, 'ok=1');
    is($result->{pressure}{effect_type}, 'corner_market', 'effect type set');
    is($result->{pressure}{faction_id}, 'syndicate', 'faction set');
    is($result->{pressure}{target_id}, $target->getCol('id'), 'target matches');
    _reload_all;
    my $scrap_after = $attacker->getCol('scrap') // 0;
    is($scrap_before - $scrap_after, $t->app->config->{pvp_cost_corner_market},
       'scrap deducted');
    # Row exists and is not consumed
    $pressures->load;
    my $rows = $pressures->find(sub {
        $_[0]->{target_id} eq $target->getCol('id')
        && !$_[0]->{target_consumed}
    });
    is(scalar @$rows, 1, 'one active pressure row created');
    is($rows->[0]->getCol('target_consumed'), 0, 'target_consumed=0');
    is($rows->[0]->getCol('attacker_consumed'), 0, 'attacker_consumed=0');
    # Clean up
    $pressures->delete($rows->[0]->getCol('id'));
    $pressures->_saveTable;
};

subtest 'happy path: spoil_lead sets attacker_consumed=1' => sub {
    _reload_all;
    my $result = $pvp->apply_pressure($attacker, $target->getCol('id'), 'syndicate', 'spoil_lead');
    is($result->{ok}, 1);
    $pressures->load;
    my $rows = $pressures->find(sub {
        $_[0]->{target_id} eq $target->getCol('id')
        && !$_[0]->{target_consumed}
    });
    is(scalar @$rows, 1, 'one row created');
    is($rows->[0]->getCol('attacker_consumed'), 1, 'attacker_consumed=1 immediately');
    # Standing should have dropped
    _reload_all;
    my $loss = $t->app->config->{pvp_splash_standing_loss} // 1;
    my $standing = $attacker->getCol('standing') // {};
    is($standing->{syndicate} // 0, -$loss, 'standing decreased by loss');
    # Reset standing
    $standing->{syndicate} // 0;
    $standing->{syndicate} = 0;
    $attacker->setCol('standing', $standing);
    $attacker->save;
    # Clean up
    $pressures->delete($rows->[0]->getCol('id'));
    $pressures->_saveTable;
};

subtest 'consume_target_effects returns correct effect' => sub {
    _reload_all;
    $pvp->apply_pressure($attacker, $target->getCol('id'), 'syndicate', 'corner_market');
    _reload_all;
    my $effects = $pvp->consume_target_effects(
        $target->getCol('id'), 'syndicate', 'on_sale');
    is(ref $effects, 'HASH', 'effects hashref returned');
    ok(exists $effects->{saturation_floor}, 'saturation_floor present for corner_market');
    # Should not find it again (consumed)
    _reload_all;
    my $again = $pvp->consume_target_effects(
        $target->getCol('id'), 'syndicate', 'on_sale');
    ok(!(exists $again->{saturation_floor}), 'already consumed');
};

subtest 'lazy-delete rows when both consumed' => sub {
    _reload_all;
    my $p = $pressures->create(
        attacker_id    => $attacker->getCol('id'),
        target_id      => $target->getCol('id'),
        faction_id     => 'syndicate',
        effect_type    => 'outbid',
        target_consumed   => 1,
        attacker_consumed => 1,
    );
    $p->save;
    my $id = $p->getCol('id');
    _reload_all;
    # A read that touches this row should delete it
    my $found = $pressures->find_active_for_target($target->getCol('id'), 'syndicate');
    _reload_all;
    ok(!$pressures->get($id), 'row was deleted after both consumed');
};

subtest 'rank_of returns correct rank' => sub {
    my $sm = $t->app->season_manager;
    is($sm->rank_of($target), 1, 'target (score 200) rank 1');
    is($sm->rank_of($attacker), 2, 'attacker (score 100) rank 2');
    is($sm->rank_of($bottom), 3, 'bottom (score 50) rank 3');
};

subtest 'build_view includes rivals' => sub {
    _reload_all;
    my $view = $pvp->build_view($attacker);
    ok(exists $view->{rivals}, 'rivals key present');
    ok(scalar @{ $view->{rivals} } > 0, 'at least one rival');
    # The target should be in rivals (ranked above attacker)
    my @rivals = grep { $_->{id} eq $target->getCol('id') } @{ $view->{rivals} };
    is(scalar @rivals, 1, 'target appears as rival');
    ok(exists $rivals[0]{pressable_factions}, 'pressable_factions key present');
};

done_testing;
