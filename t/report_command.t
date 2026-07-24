use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;
use Test::More;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use Mojo::JSON qw(encode_json);
use MagicMountain::Model::Character;

use_ok('MagicMountain::Command::report');

sub _ts { time }

sub _make_env {
    my $data_dir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $data_dir;
    $ENV{MM_SKIP_SEASON_CHECK} = 1;
    my $t = TestEnv->create_app;
    my $app = $t->app;
    $app->characters->load;
    return ($t, $app);
}

sub _add_char {
    my ($app, $name, $is_bot) = @_;
    my $c = $app->characters->create(
        name           => $name,
        account_id     => 'acct-' . $name,
        season_id      => 'season-1',
        is_bot         => $is_bot // 0,
        score          => 0,
        scrap          => 100,
        action_points  => 10,
        standing       => {},
        faction_sales  => {},
        current_location => 'home',
        current_view     => 'home',
    );
    $c->save;
    return $c->getCol('id');
}

sub _write_transcript {
    my ($app, @events) = @_;
    my $path = $app->dataDir . '/transcript.jsonl';
    my $lines = join('', map { encode_json($_) . "\n" } @events);
    write_file($path, $lines);
    return $path;
}

subtest 'empty transcript' => sub {
    my ($t, $app) = _make_env;
    _add_char($app, 'test_player', 0);
    $app->characters->load;
    my $path = _write_transcript($app);
    my $out;
    {
        local *STDOUT;
        open STDOUT, '>', \$out;
        my $cmd = MagicMountain::Command::report->new(app => $app);
        $cmd->run('--transcript', $path);
    }
    like $out, qr/Characters:\s*\d+/, 'has character count';
};

subtest 'prospecting events' => sub {
    my ($t, $app) = _make_env;
    my $cid = _add_char($app, 'test_player', 0);
    $app->characters->load;
    my @events = (
        { ts => _ts, type => 'artifact_start', char_id => $cid, artifact_id => 'a1' },
        { ts => _ts, type => 'push', char_id => $cid, stage => 2, ratio => 0.5 },
        { ts => _ts, type => 'push', char_id => $cid, stage => 3, ratio => 0.7 },
        { ts => _ts, type => 'breakthrough', char_id => $cid, artifact_id => 'a1', value => 150 },
        { ts => _ts, type => 'artifact_start', char_id => $cid, artifact_id => 'a2' },
        { ts => _ts, type => 'push', char_id => $cid, stage => 2, ratio => 0.4 },
        { ts => _ts, type => 'collapse', char_id => $cid, artifact_id => 'a2' },
    );
    my $path = _write_transcript($app, @events);
    my $out;
    {
        local *STDOUT;
        open STDOUT, '>', \$out;
        my $cmd = MagicMountain::Command::report->new(app => $app);
        $cmd->run('--transcript', $path);
    }
    like $out, qr/Expeditions.*2/, 'two expeditions';
    like $out, qr/Breakthrough.*50/, 'one breakthrough';
    like $out, qr/Collapse.*50/, 'one collapse';
};

subtest 'market events with new types' => sub {
    my ($t, $app) = _make_env;
    my $cid = _add_char($app, 'test_player', 0);
    $app->characters->load;
    my @events = (
        { ts => _ts, type => 'market_visit', char_id => $cid },
        { ts => _ts, type => 'offer', char_id => $cid, match => 1 },
        { ts => _ts, type => 'sale', char_id => $cid, value => 100, sale_type => 'direct' },
        { ts => _ts, type => 'market_visit', char_id => $cid },
        { ts => _ts, type => 'offer', char_id => $cid, match => 0 },
        { ts => _ts, type => 'offer', char_id => $cid, match => 1 },
        { ts => _ts, type => 'counter_offer', char_id => $cid },
        { ts => _ts, type => 'accept_counter', char_id => $cid },
        { ts => _ts, type => 'sale', char_id => $cid, value => 200, sale_type => 'loyalty' },
        { ts => _ts, type => 'market_visit', char_id => $cid },
        { ts => _ts, type => 'send_away', char_id => $cid },
        { ts => _ts, type => 'market_visit', char_id => $cid },
        { ts => _ts, type => 'sale_maxed', char_id => $cid },
        { ts => _ts, type => 'stand_pat', char_id => $cid, accepted => 1 },
        { ts => _ts, type => 'market_visit', char_id => $cid },
        { ts => _ts, type => 'over_budget', char_id => $cid },
        { ts => _ts, type => 'influence_snub', char_id => $cid },
        { ts => _ts, type => 'send_away', char_id => $cid },
    );
    my $path = _write_transcript($app, @events);
    my $out;
    {
        local *STDOUT;
        open STDOUT, '>', \$out;
        my $cmd = MagicMountain::Command::report->new(app => $app);
        $cmd->run('--transcript', $path);
    }
    like $out, qr/Visits.*5/, 'five visits';
    like $out, qr/Sales.*2/, 'two sales';
    like $out, qr/Sale maxed.*1/, 'one sale_maxed';
    like $out, qr/Over budget.*1/, 'one over_budget';
    like $out, qr/Influence snubs.*1/, 'one influence_snub';
    like $out, qr/Send-aways.*2/, 'two send_aways';
};

subtest 'bot/human split' => sub {
    my ($t, $app) = _make_env;
    my $cid_h = _add_char($app, 'human_player', 0);
    my $cid_b = _add_char($app, 'bot_player', 1);
    $app->characters->load;

    my @events = (
        { ts => _ts, type => 'artifact_start', char_id => $cid_h, artifact_id => 'a1' },
        { ts => _ts, type => 'push', char_id => $cid_h },
        { ts => _ts, type => 'breakthrough', char_id => $cid_h, artifact_id => 'a1', value => 100 },
        { ts => _ts, type => 'artifact_start', char_id => $cid_b, artifact_id => 'a2' },
        { ts => _ts, type => 'push', char_id => $cid_b },
        { ts => _ts, type => 'push', char_id => $cid_b },
        { ts => _ts, type => 'collapse', char_id => $cid_b, artifact_id => 'a2' },
    );
    my $path = _write_transcript($app, @events);
    my $out;
    {
        local *STDOUT;
        open STDOUT, '>', \$out;
        my $cmd = MagicMountain::Command::report->new(app => $app);
        $cmd->run('--transcript', $path);
    }
    like $out, qr/Expeditions:\s+1/s, 'bot+human each have 1 expedition';
    like $out, qr/Bot:\n.*Avg pushes.*2\.0/s, 'bot avg 2 pushes';
    like $out, qr/Human:\n.*Avg pushes.*1\.0/s, 'human avg 1 push';
};

subtest '--for-llm format' => sub {
    my ($t, $app) = _make_env;
    my $cid = _add_char($app, 'p1', 0);
    my $cid2 = _add_char($app, 'p2', 0);
    $app->characters->load;
    my @events = (
        { ts => _ts, type => 'artifact_start', char_id => $cid, artifact_id => 'a1' },
        { ts => _ts, type => 'push', char_id => $cid },
        { ts => _ts, type => 'breakthrough', char_id => $cid, artifact_id => 'a1', value => 150 },
        { ts => _ts, type => 'market_visit', char_id => $cid2 },
        { ts => _ts, type => 'offer', char_id => $cid2, match => 1 },
        { ts => _ts, type => 'sale', char_id => $cid2, value => 75, sale_type => 'direct' },
    );
    my $path = _write_transcript($app, @events);
    my $out;
    {
        local *STDOUT;
        open STDOUT, '>', \$out;
        my $cmd = MagicMountain::Command::report->new(app => $app);
        $cmd->run('--transcript', $path, '--for-llm');
    }
    like $out, qr/=PROSPECTING=/, 'has prospecting section';
    like $out, qr/=MARKET=/, 'has market section';
    like $out, qr/=SALE PRICES=/, 'has sale prices section';
    like $out, qr/characters:/, 'has character summary';
    unlike $out, qr/Expeditions:/, 'no human-table formatting';
};

subtest '--player filter by ID' => sub {
    my ($t, $app) = _make_env;
    my $cid = _add_char($app, 'target', 0);
    _add_char($app, 'other', 0);
    $app->characters->load;
    my @events = (
        { ts => _ts, type => 'artifact_start', char_id => $cid, artifact_id => 'a1' },
        { ts => _ts, type => 'push', char_id => $cid },
        { ts => _ts, type => 'breakthrough', char_id => $cid, artifact_id => 'a1' },
    );
    my $path = _write_transcript($app, @events);
    my $out;
    {
        local *STDOUT;
        open STDOUT, '>', \$out;
        my $cmd = MagicMountain::Command::report->new(app => $app);
        $cmd->run('--transcript', $path, '--player', $cid);
    }
    like $out, qr/Expeditions.*1/, 'one expedition for player';
};

subtest '--player filter by name' => sub {
    my ($t, $app) = _make_env;
    my $cid = _add_char($app, 'target_name', 0);
    _add_char($app, 'other', 0);
    $app->characters->load;
    my @events = (
        { ts => _ts, type => 'artifact_start', char_id => $cid, artifact_id => 'a1' },
        { ts => _ts, type => 'push', char_id => $cid },
        { ts => _ts, type => 'breakthrough', char_id => $cid, artifact_id => 'a1' },
    );
    my $path = _write_transcript($app, @events);
    my $out;
    {
        local *STDOUT;
        open STDOUT, '>', \$out;
        my $cmd = MagicMountain::Command::report->new(app => $app);
        $cmd->run('--transcript', $path, '--player', 'target_name');
    }
    like $out, qr/Expeditions.*1/, 'filtered by name';
};

subtest 'PVP section' => sub {
    my ($t, $app) = _make_env;
    $app->config->{pvp_cost_corner_market} = 50;
    $app->config->{pvp_cost_spoil_lead}    = 30;
    $app->config->{pvp_cost_outbid}        = 75;

    my $cid_a = _add_char($app, 'attacker', 0);
    my $cid_t = _add_char($app, 'target', 0);
    $app->characters->load;

    $app->pressures->load;
    my $p = $app->pressures->create(
        attacker_id       => $cid_a,
        target_id         => $cid_t,
        faction_id        => 'faction_a',
        effect_type       => 'corner_market',
        target_consumed   => 0,
        attacker_consumed => 1,
    );
    $p->save;
    $app->pressures->load;

    my @events = (
        { ts => _ts, type => 'market_visit', char_id => $cid_a },
        { ts => _ts, type => 'offer', char_id => $cid_a, match => 1 },
        { ts => _ts, type => 'sale', char_id => $cid_a, value => 50, sale_type => 'corner' },
    );
    my $path = _write_transcript($app, @events);
    my $out;
    {
        local *STDOUT;
        open STDOUT, '>', \$out;
        my $cmd = MagicMountain::Command::report->new(app => $app);
        $cmd->run('--transcript', $path);
    }
    like $out, qr/PVP/, 'has PVP section';
    like $out, qr/corner_market/, 'has corner_market effect';
};

subtest 'sale prices with bot/human breakdown' => sub {
    my ($t, $app) = _make_env;
    my $cid_h = _add_char($app, 'human', 0);
    my $cid_b = _add_char($app, 'bot', 1);
    $app->characters->load;

    my @events = (
        { ts => _ts, type => 'market_visit', char_id => $cid_h },
        { ts => _ts, type => 'offer', char_id => $cid_h, match => 1 },
        { ts => _ts, type => 'sale', char_id => $cid_h, value => 100, sale_type => 'direct' },
        { ts => _ts, type => 'market_visit', char_id => $cid_b },
        { ts => _ts, type => 'offer', char_id => $cid_b, match => 1 },
        { ts => _ts, type => 'sale', char_id => $cid_b, value => 50, sale_type => 'direct' },
    );
    my $path = _write_transcript($app, @events);
    my $out;
    {
        local *STDOUT;
        open STDOUT, '>', \$out;
        my $cmd = MagicMountain::Command::report->new(app => $app);
        $cmd->run('--transcript', $path, '--for-llm');
    }
    like $out, qr/=SALE PRICES=/, 'has sale prices section in llm output';
    like $out, qr/direct/, 'has direct sale type';
    like $out, qr/n=2/, 'two total sales';
};

subtest 'regression: existing table format without --for-llm' => sub {
    my ($t, $app) = _make_env;
    my $cid = _add_char($app, 'test', 0);
    $app->characters->load;
    my @events = (
        { ts => _ts, type => 'artifact_start', char_id => $cid, artifact_id => 'a1' },
        { ts => _ts, type => 'push', char_id => $cid },
        { ts => _ts, type => 'breakthrough', char_id => $cid, artifact_id => 'a1', value => 100 },
    );
    my $path = _write_transcript($app, @events);
    my $out;
    {
        local *STDOUT;
        open STDOUT, '>', \$out;
        my $cmd = MagicMountain::Command::report->new(app => $app);
        $cmd->run('--transcript', $path);
    }
    like $out, qr/Characters:/, 'has Characters header';
    like $out, qr/-- Prospecting/, 'has Prospecting header';
    like $out, qr/Expeditions:/, 'keeps human table labels';
};

done_testing;
