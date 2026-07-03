use Modern::Perl;
use Test::More;

use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::ShedManager;
use constant SHEDMGR => 'MagicMountain::ShedManager';

my $D = {
    fresh_multiplier    => 1.0,
    settling_multiplier => 0.75,
    fading_multiplier   => 0.40,
    settling_day        => 2,
    fading_day          => 5,
};

subtest 'fresh phase (day 0, day 1)' => sub {
    my ($cond, $mult) = SHEDMGR->compute_decay(0, $D);
    is $cond, 'fresh',  'day 0 condition fresh';
    is $mult, 1.0,      'day 0 mult 1.0';

    ($cond, $mult) = SHEDMGR->compute_decay(1, $D);
    is $cond, 'fresh',  'day 1 condition fresh';
    is $mult, 1.0,      'day 1 mult 1.0';
};

subtest 'settling phase (day 2-4)' => sub {
    my ($cond, $mult) = SHEDMGR->compute_decay(2, $D);
    is $cond, 'settling', 'day 2 condition settling';
    is $mult, 1.0,        'day 2 mult still 1.0 (start of settling)';

    ($cond, $mult) = SHEDMGR->compute_decay(3, $D);
    is $cond, 'settling', 'day 3 condition settling';
    cmp_ok $mult, '<', 1.0,    'day 3 mult below 1.0';
    cmp_ok $mult, '>', 0.75,   'day 3 mult above 0.75';

    ($cond, $mult) = SHEDMGR->compute_decay(4, $D);
    is $cond, 'settling', 'day 4 condition settling';
    cmp_ok $mult, '<', 1.0,    'day 4 mult below 1.0';
    cmp_ok $mult, '>', 0.75,   'day 4 mult above 0.75';
};

subtest 'fading phase (day 5+)' => sub {
    my ($cond, $mult) = SHEDMGR->compute_decay(5, $D);
    is $cond, 'fading', 'day 5 condition fading';
    is $mult, 0.75,     'day 5 mult 0.75 (settling multiplier, start of fading)';

    ($cond, $mult) = SHEDMGR->compute_decay(6, $D);
    is $cond, 'fading', 'day 6 condition fading';
    cmp_ok $mult, '<', 0.75, 'day 6 mult below 0.75';
    cmp_ok $mult, '>', 0.40, 'day 6 mult above 0.40';

    ($cond, $mult) = SHEDMGR->compute_decay(10, $D);
    is $cond, 'fading', 'day 10 condition fading';
    cmp_ok $mult, '<=', 0.40, 'day 10 mult at or below fading floor';
};

subtest 'decayed_value calculation' => sub {
    my $orig = 20;
    my ($cond, $mult) = SHEDMGR->compute_decay(0, $D);
    is int($orig * $mult), 20, 'day 0: full value';

    ($cond, $mult) = SHEDMGR->compute_decay(5, $D);
    is int($orig * $mult), 15, 'day 5: 75% of 20 = 15';

    ($cond, $mult) = SHEDMGR->compute_decay(10, $D);
    is int($orig * $mult), 8, 'day 10: floored at 40% of 20 = 8';
};

subtest 'estimated value range' => sub {
    my $orig = 20;
    my ($cond, $mult) = SHEDMGR->compute_decay(3, $D);
    my $decayed = int($orig * $mult);
    my $est_min = int($decayed * 0.8);
    my $est_max = int($decayed * 1.2);
    cmp_ok $est_min, '<=', $est_max, 'est_min <= est_max';
    cmp_ok $est_min, '>',  0,        'est_min positive';
};

subtest 'consistent daily decay rate' => sub {
    my @mults;
    for my $d (2 .. 10) {
        my (undef, $mult) = SHEDMGR->compute_decay($d, $D);
        push @mults, $mult;
    }
    for my $i (1 .. $#mults) {
        my $drop = $mults[$i-1] - $mults[$i];
        cmp_ok $drop, '>',  0,       "monotonic drop day " . ($i+1);
        cmp_ok $drop, '<',  0.2,     "drop not excessive: $drop";
    }
};

subtest 'undef modifiers — uses defaults' => sub {
    my ($cond, $mult) = SHEDMGR->compute_decay(5, undef);
    is $cond, 'fading', 'undef mods: still fading at day 5';
    is $mult, 0.75,     'undef mods: falls back to defaults';

    ($cond, $mult) = SHEDMGR->compute_decay(0, undef);
    is $cond, 'fresh',  'undef mods: fresh at day 0';
    is $mult, 1.0,      'undef mods: mult 1.0';
};

subtest 'custom thresholds' => sub {
    my $fast = {
        fresh_multiplier    => 1.0,
        settling_multiplier => 0.50,
        fading_multiplier   => 0.10,
        settling_day        => 1,
        fading_day          => 3,
    };
    my ($cond, $mult) = SHEDMGR->compute_decay(0, $fast);
    is $cond, 'fresh',   'custom: day 0 fresh';
    is $mult, 1.0,       'custom: day 0 mult 1.0';

    ($cond, $mult) = SHEDMGR->compute_decay(3, $fast);
    is $cond, 'fading', 'custom: day 3 fading';
    is $mult, 0.50,     'custom: day 3 mult 0.50 (settling at fading_day)';
};

subtest 'zero original value' => sub {
    my ($cond, $mult) = SHEDMGR->compute_decay(10, $D);
    is int(0 * $mult), 0, 'zero original: decayed_value stays 0';
};

subtest 'apply_decay integration with real Model::ShedItem' => sub {
    use File::Temp qw(tempdir);
    use MagicMountain::Model::ShedItem;

    my $dir = tempdir(CLEANUP => 1);
    my $file = "$dir/shed.json";

    my $model = MagicMountain::Model::ShedItem->new(file => $file);
    my $id1 = 'test-item-1';
    my $id2 = 'test-item-2';

    $model->load;
    $model->table->{$id1} = {
        id                  => $id1,
        char_id             => 'char-1',
        artifact_id         => 'thermal_box_001',
        original_value      => 20,
        decayed_value       => 20,
        condition           => 'fresh',
        days_in_shed        => 0,
        instability         => 5,
        stage               => 'strained',
        push_count          => 2,
        has_evolved         => 0,
        behaviors           => ['thermal'],
        archetypes          => ['energy'],
        estimated_value_min => 16,
        estimated_value_max => 24,
        decay_modifiers     => $D,
    };
    $model->table->{$id2} = {
        id                  => $id2,
        char_id             => 'char-2',
        artifact_id         => 'crystal_chime_001',
        original_value      => 30,
        decayed_value       => 30,
        condition           => 'fresh',
        days_in_shed        => 0,
        instability         => 3,
        stage               => 'stable',
        push_count          => 1,
        has_evolved         => 0,
        behaviors           => ['signal'],
        archetypes          => ['resonance'],
        estimated_value_min => 24,
        estimated_value_max => 36,
        decay_modifiers     => $D,
    };
    $model->save;

    {
        package FakeApp::DecayTest;
        sub new { bless { shed => undef, log => bless({}, 'FakeLog::DecayTest') }, shift }
        sub shed { shift->{shed} }
        sub log  { shift->{log} }
    }
    {
        package FakeLog::DecayTest;
        sub debug { 1 }
    }

    my $shed_mgr = MagicMountain::ShedManager->new(app => FakeApp::DecayTest->new);
    $shed_mgr->app->{shed} = $model;

    $shed_mgr->apply_decay;

    my $item1 = $shed_mgr->app->shed->get($id1);
    is $item1->getCol('days_in_shed'), 1,            'item1 days_in_shed incremented';
    is $item1->getCol('condition'),    'fresh',       'item1 still fresh at day 1';
    is $item1->getCol('decayed_value'), 20,           'item1 value unchanged at day 1';

    $shed_mgr->apply_decay;

    my $item1b = $shed_mgr->app->shed->get($id1);
    is $item1b->getCol('days_in_shed'), 2,            'item1 day 2';
    is $item1b->getCol('condition'),    'settling',    'item1 now settling';
    is $item1b->getCol('decayed_value'), 20,           'item1 value still 20 (settling day 2 = fresh mult)';

    $shed_mgr->apply_decay;
    $shed_mgr->apply_decay;
    $shed_mgr->apply_decay;

    my $item1c = $shed_mgr->app->shed->get($id1);
    is $item1c->getCol('days_in_shed'), 5,            'item1 day 5';
    is $item1c->getCol('condition'),    'fading',      'item1 now fading';
    is $item1c->getCol('decayed_value'), 15,           'item1 value 15 (75% of 20)';
};

done_testing;
