use Modern::Perl;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Service::SkillTraining;
use TestCharacter;

sub _build_app {
    my $dataDir = tempdir(CLEANUP => 1);
    $ENV{MM_DATA_DIR} = $dataDir;
    local $ENV{MOJO_MODE} = 'test';
    my $t = Test::Mojo->new('MagicMountain');
    return $t->app;
}

subtest 'purchase — success deducts scrap and increases level' => sub {
    my $app = _build_app();
    my $svc = MagicMountain::Service::SkillTraining->new(app => $app);

    my $char = TestCharacter->new(
        skill_prospecting => 0,
        scrap => 500,
        action_points => 15,
        score => 0,
    );

    my $result = $svc->purchase($char, 'prospecting');
    ok $result->{ok}, 'purchase succeeded';
    is $char->{skill_prospecting}, 1, 'skill increased to 1';
    ok $char->{scrap} < 500, 'scrap decreased';
    ok exists $result->{player}, 'response includes player data';
};

subtest 'purchase — unknown skill returns error' => sub {
    my $app = _build_app();
    my $svc = MagicMountain::Service::SkillTraining->new(app => $app);
    my $char = TestCharacter->new(scrap => 500);

    my $result = $svc->purchase($char, 'nonexistent');
    ok !$result->{ok}, 'purchase failed';
    is $result->{error}, 'unknown skill';
};

subtest 'purchase — already at max returns error' => sub {
    my $app = _build_app();
    my $svc = MagicMountain::Service::SkillTraining->new(app => $app);
    my $char = TestCharacter->new(
        skill_prospecting => 4,
        scrap => 9999,
    );

    my $result = $svc->purchase($char, 'prospecting');
    ok !$result->{ok}, 'purchase failed';
    is $result->{error}, 'already at max';
};

subtest 'purchase — insufficient scrap returns error' => sub {
    my $app = _build_app();
    my $svc = MagicMountain::Service::SkillTraining->new(app => $app);
    my $char = TestCharacter->new(
        skill_prospecting => 0,
        scrap => 0,
    );

    my $result = $svc->purchase($char, 'prospecting');
    ok !$result->{ok}, 'purchase failed';
    is $result->{error}, 'not enough scrap';
};

subtest 'purchase — multiple levels cost increasing scrap' => sub {
    my $app = _build_app();
    my $svc = MagicMountain::Service::SkillTraining->new(app => $app);
    my $char = TestCharacter->new(
        skill_prospecting => 0,
        scrap => 9999,
    );

    my $prev_scrap = $char->{scrap};
    for my $level (1..4) {
        my $result = $svc->purchase($char, 'prospecting');
        ok $result->{ok}, "level $level purchase succeeded";
        is $char->{skill_prospecting}, $level, "skill at level $level";
        ok $char->{scrap} < $prev_scrap, "scrap decreased for level $level";
        $prev_scrap = $char->{scrap};
    }

    my $result = $svc->purchase($char, 'prospecting');
    ok !$result->{ok}, 'cannot purchase beyond max';
    is $result->{error}, 'already at max';
};

subtest 'skill_list — returns skills with current levels' => sub {
    my $app = _build_app();
    my $svc = MagicMountain::Service::SkillTraining->new(app => $app);
    my $char = TestCharacter->new(
        skill_prospecting => 2,
        skill_upcycling   => 0,
        skill_selling     => 1,
        scrap => 500,
    );

    my $result = $svc->skill_list($char);
    ok $result->{skills}, 'has skills list';
    is $result->{scrap}, 500, 'scrap in response';

    my ($prospecting) = grep { $_->{id} eq 'prospecting' } @{ $result->{skills} };
    is $prospecting->{current_level}, 2, 'prospecting level correct';

    my ($upcycling) = grep { $_->{id} eq 'upcycling' } @{ $result->{skills} };
    is $upcycling->{current_level}, 0, 'upcycling level correct';

    my ($selling) = grep { $_->{id} eq 'selling' } @{ $result->{skills} };
    is $selling->{current_level}, 1, 'selling level correct';
};

done_testing;
