use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;
use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(write_file);

use_ok('MagicMountain::Model::Character');

my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
write_file($file, '{}');

my $char = MagicMountain::Model::Character->new(file => $file);

subtest 'score never decreases' => sub {
    $char->setCol('score', 5);
    $char->setCol('score', 8);  # increase OK
    is($char->getCol('score'), 8, 'score increased to 8');

    eval { $char->setCol('score', 3) };
    like($@, qr/invariant: score/, 'score decrease dies');
};

subtest 'score set on new char' => sub {
    my $c = $char->create(name => 't', account_id => 'a', season_id => 's');
    $c->setCol('score', 10);
    is($c->getCol('score'), 10, 'first score assignment succeeds');
};

subtest 'scrap non-negative' => sub {
    $char->setCol('scrap', 50);
    is($char->getCol('scrap'), 50, 'positive scrap OK');

    eval { $char->setCol('scrap', -1) };
    like($@, qr/invariant: scrap/, 'negative scrap dies');
};

subtest 'action_points bounded by max' => sub {
    $char->setCol('action_points_max', 15);

    $char->setCol('action_points', 15);
    is($char->getCol('action_points'), 15, 'AP at max OK');

    $char->setCol('action_points', 0);
    is($char->getCol('action_points'), 0, 'AP zero OK');

    eval { $char->setCol('action_points', 16) };
    like($@, qr/invariant: action_points/, 'AP above max dies');
};

subtest 'skills clamped 0-4' => sub {
    $char->setCol('skill_prospecting', 4);
    is($char->getCol('skill_prospecting'), 4, 'skill 4 OK (invariant relaxed)');

    eval { $char->setCol('skill_prospecting', 5) };
    like($@, qr/must be 0-4/, 'skill above 4 dies');

    eval { $char->setCol('skill_prospecting', -1) };
    like($@, qr/must be 0-4/, 'skill below 0 dies');
};

subtest 'non-invariant column passes through' => sub {
    $char->setCol('name', 'bob');
    is($char->getCol('name'), 'bob', 'name set succeeds');
};

done_testing;
