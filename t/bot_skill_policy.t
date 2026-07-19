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

sub _state {
    my %levels = @_;
    my $out = [];
    for my $s (@$skills) {
        my $s2 = { %$s };
        $s2->{current_level} = $levels{ $s->{id} } // 0;
        push @$out, $s2;
    }
    return $out;
}

subtest 'immediate policy buys cheapest affordable' => sub {
    my $state = { scrap => 200 };
    my $s = _state(prospecting => 0, upcycling => 0, selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($state,
        { name => 'immediate', params => { reserve => 30 } }, $s);

    ok($d, 'decided to buy a skill');
    is($d->{skill_id}, 'prospecting', 'cheapest (prospecting 1, cost 100) is chosen');
    is($d->{cost}, 100, 'cost is 100');
    is($d->{level}, 1, 'level is 1');
};

subtest 'immediate policy respects reserve' => sub {
    my $state = { scrap => 130 };
    my $s = _state(prospecting => 0, upcycling => 0, selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($state,
        { name => 'immediate', params => { reserve => 30 } }, $s);
    ok($d, 'decided (130 >= 100 + 30)');

    $state = { scrap => 129 };
    $d = MagicMountain::Bot::SkillPolicy::decide($state,
        { name => 'immediate', params => { reserve => 30 } }, $s);
    ok(!$d, 'skipped (129 < 100 + 30)');
};

subtest 'immediate sorts by cost ascending' => sub {
    my $state = { scrap => 500 };
    my $s = _state(prospecting => 1, upcycling => 0, selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($state,
        { name => 'immediate', params => { reserve => 30 } }, $s);

    ok($d, 'decided');
    is($d->{skill_id}, 'upcycling', 'upcycling 1 (100) is cheaper than prospecting 2 (250)');
    is($d->{cost}, 100, 'cost is 100');
};

subtest 'specialize buys from priority tree first' => sub {
    my $state = { scrap => 500 };
    my $s = _state(prospecting => 0, upcycling => 0, selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($state,
        { name => 'specialize', params => { priority => ['selling'], reserve => 30 } }, $s);

    ok($d, 'decided');
    is($d->{skill_id}, 'selling', 'selling is first priority');
    is($d->{level}, 1, 'level 1');
};

subtest 'specialize maxes out priority before moving on' => sub {
    my $state = { scrap => 120 };
    my $s = _state(prospecting => 0, upcycling => 0, selling => 3);

    my $d = MagicMountain::Bot::SkillPolicy::decide($state,
        { name => 'specialize', params => { priority => ['selling', 'prospecting'], reserve => 30 } }, $s);
    ok(!$d, 'selling is maxed (lv3), but 120 < 100+30 for prospecting 1');

    $state = { scrap => 130 };
    $d = MagicMountain::Bot::SkillPolicy::decide($state,
        { name => 'specialize', params => { priority => ['selling', 'prospecting'], reserve => 30 } }, $s);
    ok($d, 'decided to buy prospecting after selling maxed');
    is($d->{skill_id}, 'prospecting', 'moved to next priority');
};

subtest 'never never buys' => sub {
    my $state = { scrap => 9999 };
    my $s = _state(prospecting => 0, upcycling => 0, selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($state,
        { name => 'never' }, $s);
    ok(!$d, 'never policy returns nothing');

    $d = MagicMountain::Bot::SkillPolicy::decide($state,
        { name => 'never', params => {} }, $s);
    ok(!$d, 'never policy with empty params returns nothing');
};

subtest 'unknown policy name falls back to never' => sub {
    my $state = { scrap => 9999 };
    my $s = _state(prospecting => 0, upcycling => 0, selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($state,
        { name => 'nonexistent_policy' }, $s);
    ok(!$d, 'unknown policy falls back to never');
};

subtest 'missing policy defaults to never' => sub {
    my $state = { scrap => 9999 };
    my $s = _state(prospecting => 0, upcycling => 0, selling => 0);

    my $d = MagicMountain::Bot::SkillPolicy::decide($state, {}, $s);
    ok(!$d, 'missing policy defaults to never');
};

subtest 'all skills maxed returns nothing' => sub {
    my $state = { scrap => 9999 };
    my $s = _state(prospecting => 4, upcycling => 4, selling => 3);

    my $d = MagicMountain::Bot::SkillPolicy::decide($state,
        { name => 'immediate', params => { reserve => 0 } }, $s);
    ok(!$d, 'all skills maxed, nothing to buy');
};

done_testing;
