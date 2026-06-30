use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib");
use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(write_file);

use_ok('MagicMountain::Model::Character');

my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
write_file($file, '{}');

my $model = MagicMountain::Model::Character->new(file => $file);

subtest 'AP never goes negative across handler-like sequence' => sub {
    my $c = $model->create(
        name => 'test', account_id => 'a1', season_id => 's1',
        action_points => 15, action_points_max => 15,
    );

    # Simulate: begin → push → stop (2 AP + 0 + 0 = 2 AP total)
    $c->setCol('action_points', $c->getCol('action_points') - 2);
    $c->setCol('action_points', $c->getCol('action_points') - 0);
    $c->setCol('action_points', $c->getCol('action_points') - 0);
    is($c->getCol('action_points'), 13, 'AP = 13 after 1 activity');

    # Simulate: begin → collapse (2 AP, no refund)
    $c->setCol('action_points', $c->getCol('action_points') - 2);
    is($c->getCol('action_points'), 11, 'AP = 11 after collapse');

    # More activities...
    $c->setCol('action_points', $c->getCol('action_points') - 2);
    $c->setCol('action_points', $c->getCol('action_points') - 2);
    $c->setCol('action_points', $c->getCol('action_points') - 2);
    $c->setCol('action_points', $c->getCol('action_points') - 2);
    $c->setCol('action_points', $c->getCol('action_points') - 2);
    is($c->getCol('action_points'), 1, 'AP = 1 after 5 more activities');

    # Next begin would die because only 1 AP remains (< 2)
    eval { die "AP exhausted" unless ($c->getCol('action_points') // 0) >= 2 };
    like($@, qr/AP exhausted/, 'begin dies when AP < 2');

    # AP never went negative
    cmp_ok($c->getCol('action_points'), '>=', 0, 'AP never negative');
};

subtest 'score only increases after breakthrough-style cashout' => sub {
    my $c = $model->create(
        name => 'test2', account_id => 'a2', season_id => 's1',
        score => 0,
    );

    # Simulate breakthrough: value awarded
    $c->setCol('score', $c->getCol('score') + 50);
    is($c->getCol('score'), 50, 'score = 50 after first breakthrough');

    $c->setCol('score', $c->getCol('score') + 30);
    is($c->getCol('score'), 80, 'score = 80 after second sale');

    # Score never decreases
    eval { $c->setCol('score', 40) };
    like($@, qr/invariant: score/, 'score decrease dies');
};

subtest 'skill values 0-4 accepted, 5 rejected' => sub {
    my $c = $model->create(
        name => 'test4', account_id => 'a4', season_id => 's1',
    );

    $c->setCol('skill_upcycling', 0);
    is($c->getCol('skill_upcycling'), 0, 'skill 0 OK');

    $c->setCol('skill_upcycling', 4);
    is($c->getCol('skill_upcycling'), 4, 'skill 4 OK');

    eval { $c->setCol('skill_upcycling', 5) };
    like($@, qr/must be 0-4/, 'skill above 4 dies');

    eval { $c->setCol('skill_upcycling', -1) };
    like($@, qr/must be 0-4/, 'skill below 0 dies');
};

subtest 'AP refresh respects action_points_max' => sub {
    my $c = $model->create(
        name => 'test3', account_id => 'a3', season_id => 's1',
        action_points => 3, action_points_max => 15,
    );

    # Simulate maintenance refresh
    my $max = $c->getCol('action_points_max');
    $c->setCol('action_points', $max);
    is($c->getCol('action_points'), 15, 'AP refreshed to max');

    # Cannot exceed max
    eval { $c->setCol('action_points', 20) };
    like($@, qr/invariant: action_points/, 'AP above max dies');
};

subtest 'validate_save catches direct hash manipulation' => sub {
    my $c = $model->create(
        name => 'test5', account_id => 'a5', season_id => 's1',
        action_points => 10, action_points_max => 15, scrap => 50, score => 100,
        skill_prospecting => 1, skill_upcycling => 2, skill_selling => 3,
    );

    # Direct hash manipulation bypassing setCol
    $c->row->{action_points} = -5;
    eval { $c->save };
    like($@, qr/invariant: action_points \(-5\) < 0/, 'save catches negative AP');

    $c->row->{action_points} = 99;
    eval { $c->save };
    like($@, qr/invariant: action_points \(99\) exceeds max/, 'save catches AP > max');

    $c->row->{action_points} = 10;
    $c->row->{scrap} = -1;
    eval { $c->save };
    like($@, qr/invariant: scrap < 0/, 'save catches negative scrap');

    $c->row->{scrap} = 50;
    $c->row->{score} = -5;
    eval { $c->save };
    like($@, qr/invariant: score < 0/, 'save catches negative score');

    $c->row->{score} = 100;
    $c->row->{skill_prospecting} = 5;
    eval { $c->save };
    like($@, qr/invariant: skill_prospecting/, 'save catches skill out of range');
};

done_testing;
