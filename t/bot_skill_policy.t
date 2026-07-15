use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;
use Test::More;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use TestCharacter;

use_ok('MagicMountain::Bot::SkillPolicy');

# Build mock skills data matching content/skills.yml
my $skills = [
    { id => 'prospecting', max_level => 4, levels => [
        { level => 1, cost => 100 },
        { level => 2, cost => 250 },
        { level => 3, cost => 500 },
        { level => 4, cost => 1000 },
    ]},
    { id => 'upcycling', max_level => 4, levels => [
        { level => 1, cost => 100 },
        { level => 2, cost => 250 },
        { level => 3, cost => 500 },
        { level => 4, cost => 1000 },
    ]},
    { id => 'selling', max_level => 3, levels => [
        { level => 1, cost => 100 },
        { level => 2, cost => 250 },
        { level => 3, cost => 500 },
    ]},
];

subtest 'immediate policy buys cheapest affordable' => sub {
    my $char = _mock_char(scrap => 200,
        skill_prospecting => 0, skill_upcycling => 0, skill_selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($char,
        { name => 'immediate', params => { reserve => 30 } }, $skills, undef);

    ok($d, 'decided to buy a skill');
    is($d->{skill_id}, 'prospecting', 'cheapest (prospecting 1, cost 100) is chosen');
    is($d->{cost}, 100, 'cost is 100');
    is($d->{level}, 1, 'level is 1');
};

subtest 'immediate policy respects reserve' => sub {
    my $char = _mock_char(scrap => 130,
        skill_prospecting => 0, skill_upcycling => 0, skill_selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($char,
        { name => 'immediate', params => { reserve => 30 } }, $skills, undef);

    ok($d, 'decided (130 >= 100 + 30)');

    $char = _mock_char(scrap => 129,
        skill_prospecting => 0, skill_upcycling => 0, skill_selling => 0);

    $d = MagicMountain::Bot::SkillPolicy::decide($char,
        { name => 'immediate', params => { reserve => 30 } }, $skills, undef);

    ok(!$d, 'skipped (129 < 100 + 30)');
};

subtest 'immediate sorts by cost ascending' => sub {
    my $char = _mock_char(scrap => 500, skill_prospecting => 1, skill_upcycling => 0, skill_selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($char,
        { name => 'immediate', params => { reserve => 30 } }, $skills, undef);

    ok($d, 'decided');
    is($d->{skill_id}, 'upcycling', 'upcycling 1 (100) is cheaper than prospecting 2 (250)');
    is($d->{cost}, 100, 'cost is 100');
};

subtest 'specialize buys from priority tree first' => sub {
    my $char = _mock_char(scrap => 500,
        skill_prospecting => 0, skill_upcycling => 0, skill_selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($char,
        { name => 'specialize', params => { priority => ['selling'], reserve => 30 } },
        $skills, undef);

    ok($d, 'decided');
    is($d->{skill_id}, 'selling', 'selling is first priority');
    is($d->{level}, 1, 'level 1');
};

subtest 'specialize maxes out priority before moving on' => sub {
    my $char = _mock_char(scrap => 120,
        skill_prospecting => 0, skill_upcycling => 0, skill_selling => 3);

    my $d = MagicMountain::Bot::SkillPolicy::decide($char,
        { name => 'specialize', params => { priority => ['selling', 'prospecting'], reserve => 30 } },
        $skills, undef);

    ok(!$d, 'selling is maxed (lv3), but 120 < 100+30 for prospecting 1');

    $char = _mock_char(scrap => 130,
        skill_prospecting => 0, skill_upcycling => 0, skill_selling => 3);

    $d = MagicMountain::Bot::SkillPolicy::decide($char,
        { name => 'specialize', params => { priority => ['selling', 'prospecting'], reserve => 30 } },
        $skills, undef);

    ok($d, 'decided to buy prospecting after selling maxed');
    is($d->{skill_id}, 'prospecting', 'moved to next priority');
};

subtest 'never never buys' => sub {
    my $char = _mock_char(scrap => 9999,
        skill_prospecting => 0, skill_upcycling => 0, skill_selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($char,
        { name => 'never' }, $skills, undef);
    ok(!$d, 'never policy returns nothing');

    $d = MagicMountain::Bot::SkillPolicy::decide($char,
        { name => 'never', params => {} }, $skills, undef);
    ok(!$d, 'never policy with empty params returns nothing');
};

subtest 'unknown policy name falls back to never' => sub {
    my $char = _mock_char(scrap => 9999,
        skill_prospecting => 0, skill_upcycling => 0, skill_selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($char,
        { name => 'nonexistent_policy' }, $skills, undef);
    ok(!$d, 'unknown policy falls back to never');
};

subtest 'missing policy defaults to never' => sub {
    my $char = _mock_char(scrap => 9999,
        skill_prospecting => 0, skill_upcycling => 0, skill_selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($char, {}, $skills, undef);
    ok(!$d, 'missing policy defaults to never');
};

subtest 'all skills maxed returns nothing' => sub {
    my $char = _mock_char(scrap => 9999,
        skill_prospecting => 4, skill_upcycling => 4, skill_selling => 3);

    my $d = MagicMountain::Bot::SkillPolicy::decide($char,
        { name => 'immediate', params => { reserve => 0 } }, $skills, undef);
    ok(!$d, 'all skills maxed, nothing to buy');
};

sub _mock_char {
    my %cols = @_;
    return bless {
        row => \%cols,
    }, 'MockChar';
}

{
    package MockChar;
    sub getCol { my ($self, $col) = @_; return $self->{row}{$col} // 0; }
}

subtest 'test_botrunner_skill_buying' => sub {
    use Test::Mojo;

    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    local $ENV{MOJO_MODE} = 'test';

    write_file("$dataDir/magic_mountain.yml", "---\npvp_enabled: 0\n");
    $ENV{MM_CFG_FILE} = "$dataDir/magic_mountain.yml";

    my $t    = Test::Mojo->new('MagicMountain');
    my $app  = $t->app;
    my $char = TestCharacter->new(
        name              => 'bot-test',
        scrap             => 500,
        action_points     => 0,
        skill_prospecting => 0,
        skill_upcycling   => 0,
        skill_selling     => 0,
    );

    my $events = [];
    my $mock_transcript = bless { events => $events }, 'MockTranscript';
    my $runner = $app->bot_runner;
    $runner->transcript($mock_transcript);

    my $profile = {
        id          => 'test_immediate',
        push_policy => { name => 'greed', params => { prob => 0.8 } },
        sell_policy => { name => 'desperate' },
        skill_policy => { name => 'immediate', params => { reserve => 30 } },
    };

    my $result = $runner->run_day($char, $profile);
    ok($result->{ok}, 'run_day succeeded');

    my $sk = $char->getCol('skill_prospecting') // 0;
    cmp_ok($sk, '>', 0, 'skill_prospecting increased from 0');

    my @policy_events = grep { $_->{type} eq 'policy_skill_purchase' } @$events;
    cmp_ok(scalar @policy_events, '==', 1, 'policy_skill_purchase event logged');
    ok($policy_events[0]{skill_id}, 'skill_id present');
    ok($policy_events[0]{cost},     'cost present');
};

subtest 'test_botrunner_skill_buying_cap' => sub {
    use Test::Mojo;

    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    local $ENV{MOJO_MODE} = 'test';

    write_file("$dataDir/magic_mountain.yml", "---\npvp_enabled: 0\n");
    $ENV{MM_CFG_FILE} = "$dataDir/magic_mountain.yml";

    my $t    = Test::Mojo->new('MagicMountain');
    my $app  = $t->app;
    my $char = TestCharacter->new(
        name              => 'bot-cap-test',
        scrap             => 9999,
        action_points     => 0,
        skill_prospecting => 0,
        skill_upcycling   => 0,
        skill_selling     => 0,
    );

    my $events = [];
    my $mock_transcript = bless { events => $events }, 'MockTranscript';
    my $runner = $app->bot_runner;
    $runner->transcript($mock_transcript);

    my $profile = {
        id          => 'test_cap',
        push_policy => { name => 'greed', params => { prob => 0.8 } },
        sell_policy => { name => 'desperate' },
        skill_policy => { name => 'immediate', params => { reserve => 10 } },
    };

    $runner->run_day($char, $profile);

    my $sp = $char->getCol('skill_prospecting') // 0;
    my $su = $char->getCol('skill_upcycling')   // 0;
    my $ss = $char->getCol('skill_selling')     // 0;
    my $total = $sp + $su + $ss;
    is($total, 1, 'only 1 skill level purchased (cap at 1 per day)');

    my @policy_events = grep { $_->{type} eq 'policy_skill_purchase' } @$events;
    is(scalar @policy_events, 1, 'exactly 1 policy_skill_purchase event');
};

{
    package MockTranscript;
    sub log_event {
        my ($self, $data) = @_;
        push @{$self->{events}}, $data;
    }
}

done_testing;
