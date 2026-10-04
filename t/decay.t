use Modern::Perl;
use feature 'signatures';
use Test::More;

use File::Temp qw(tempdir);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Model::ShedItem;

my $D = {
    fresh_multiplier    => 1.0,
    settling_multiplier => 0.75,
    fading_multiplier   => 0.40,
    settling_day        => 2,
    fading_day          => 5,
};

my $FAST = {
    fresh_multiplier    => 1.0,
    settling_multiplier => 0.50,
    fading_multiplier   => 0.10,
    settling_day        => 1,
    fading_day          => 3,
};

# A model bound to a throwaway state file, with the default `say`-ing logger
# silenced so _saveTable/load debug lines do not pollute test output.
sub shed_model ($file) {
    my $model = MagicMountain::Model::ShedItem->new(file => $file, log => sub { });
    $model->load;
    return $model;
}

# Create a shed item via the model API and return a fresh handle to it.
# Never pokes $model->table directly -- that bypasses column validation.
sub make_item ($model, %over) {
    my $row = $model->create(
        char_id             => 'char-1',
        artifact_id         => 'probe_001',
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
        %over,
    );
    $row->save;
    return $model->get($row->getCol('id'));
}

subtest 'fresh phase (day 0, day 1)' => sub {
    my $dir  = tempdir(CLEANUP => 1);
    my $item = make_item(shed_model("$dir/shed.json"), decay_modifiers => $D);

    my ($cond, $mult) = $item->compute_decay(0);
    is $cond, 'fresh', 'day 0 condition fresh';
    is $mult, 1.0,     'day 0 mult 1.0';

    ($cond, $mult) = $item->compute_decay(1);
    is $cond, 'fresh', 'day 1 condition fresh';
    is $mult, 1.0,     'day 1 mult 1.0';
};

subtest 'settling phase (day 2-4)' => sub {
    my $dir  = tempdir(CLEANUP => 1);
    my $item = make_item(shed_model("$dir/shed.json"), decay_modifiers => $D);

    my ($cond, $mult) = $item->compute_decay(2);
    is $cond, 'settling', 'day 2 condition settling';
    is $mult, 1.0,        'day 2 mult still 1.0 (start of settling)';

    ($cond, $mult) = $item->compute_decay(3);
    is $cond, 'settling', 'day 3 condition settling';
    cmp_ok $mult, '<', 1.0,  'day 3 mult below 1.0';
    cmp_ok $mult, '>', 0.75, 'day 3 mult above 0.75';

    ($cond, $mult) = $item->compute_decay(4);
    is $cond, 'settling', 'day 4 condition settling';
    cmp_ok $mult, '<', 1.0,  'day 4 mult below 1.0';
    cmp_ok $mult, '>', 0.75, 'day 4 mult above 0.75';
};

subtest 'fading phase (day 5+)' => sub {
    my $dir  = tempdir(CLEANUP => 1);
    my $item = make_item(shed_model("$dir/shed.json"), decay_modifiers => $D);

    my ($cond, $mult) = $item->compute_decay(5);
    is $cond, 'fading', 'day 5 condition fading';
    is $mult, 0.75,     'day 5 mult 0.75 (settling multiplier, start of fading)';

    ($cond, $mult) = $item->compute_decay(6);
    is $cond, 'fading', 'day 6 condition fading';
    cmp_ok $mult, '<', 0.75, 'day 6 mult below 0.75';
    cmp_ok $mult, '>', 0.40, 'day 6 mult above 0.40';

    ($cond, $mult) = $item->compute_decay(10);
    is $cond, 'fading', 'day 10 condition fading';
    cmp_ok $mult, '<=', 0.40, 'day 10 mult at or below fading floor';
};

subtest 'decayed_value calculation' => sub {
    my $dir  = tempdir(CLEANUP => 1);
    my $item = make_item(shed_model("$dir/shed.json"), decay_modifiers => $D);

    my (undef, $mult) = $item->compute_decay(0);
    is int(20 * $mult), 20, 'day 0: full value';

    (undef, $mult) = $item->compute_decay(5);
    is int(20 * $mult), 15, 'day 5: 75% of 20 = 15';

    (undef, $mult) = $item->compute_decay(10);
    is int(20 * $mult), 8, 'day 10: floored at 40% of 20 = 8';
};

subtest 'consistent daily decay rate' => sub {
    my $dir  = tempdir(CLEANUP => 1);
    my $item = make_item(shed_model("$dir/shed.json"), decay_modifiers => $D);

    my @mults;
    for my $d (2 .. 10) {
        my (undef, $mult) = $item->compute_decay($d);
        push @mults, $mult;
    }
    for my $i (1 .. $#mults) {
        my $drop = $mults[$i-1] - $mults[$i];
        cmp_ok $drop, '>',  0,     'monotonic drop day ' . ($i+1);
        cmp_ok $drop, '<=', 0.2,   'drop not excessive: ' . $drop;
    }
};

subtest 'undef decay_modifiers -- uses defaults' => sub {
    my $dir  = tempdir(CLEANUP => 1);
    my $item = make_item(shed_model("$dir/shed.json"), decay_modifiers => undef);

    my ($cond, $mult) = $item->compute_decay(5);
    is $cond, 'fading', 'undef mods: still fading at day 5';
    is $mult, 0.75,     'undef mods: falls back to defaults';

    ($cond, $mult) = $item->compute_decay(0);
    is $cond, 'fresh',  'undef mods: fresh at day 0';
    is $mult, 1.0,      'undef mods: mult 1.0';
};

subtest 'partial decay_modifiers -- missing keys filled from defaults' => sub {
    my $dir  = tempdir(CLEANUP => 1);
    my $item = make_item(shed_model("$dir/shed.json"), decay_modifiers => { fresh_multiplier => 0.9 });

    my ($cond, $mult) = $item->compute_decay(5);
    is $cond, 'fading',                    'partial mods: condition from default fading_day';
    is $mult, 0.75,                         'partial mods: mult from default settling_multiplier';
    is $item->getCol('decay_modifiers')->{fresh_multiplier}, 0.9, 'partial mods: explicit key untouched';
};

subtest 'custom thresholds' => sub {
    my $dir  = tempdir(CLEANUP => 1);
    my $item = make_item(shed_model("$dir/shed.json"), decay_modifiers => $FAST);

    my ($cond, $mult) = $item->compute_decay(0);
    is $cond, 'fresh',   'custom: day 0 fresh';
    is $mult, 1.0,       'custom: day 0 mult 1.0';

    ($cond, $mult) = $item->compute_decay(3);
    is $cond, 'fading', 'custom: day 3 fading';
    is $mult, 0.50,     'custom: day 3 mult 0.50 (settling at fading_day)';
};

subtest 'zero original value' => sub {
    my $dir  = tempdir(CLEANUP => 1);
    my $item = make_item(shed_model("$dir/shed.json"), decay_modifiers => $D, original_value => 0, decayed_value => 0);

    my ($cond, $mult) = $item->compute_decay(10);
    is $cond, 'fading', 'zero original: condition still advances';
    is int(0 * $mult), 0, 'zero original: decayed_value stays 0';
};

subtest 'compute_decay with no arg reads days_in_shed from the row' => sub {
    my $dir  = tempdir(CLEANUP => 1);
    my $item = make_item(shed_model("$dir/shed.json"), decay_modifiers => $D, days_in_shed => 5);

    my ($cond, $mult) = $item->compute_decay();
    is $cond, 'fading', 'no-arg call: condition derived from days_in_shed';
    is $mult, 0.75,     'no-arg call: mult derived from days_in_shed';

    my ($c2, $m2) = $item->compute_decay(0);
    is $c2, 'fresh',    'explicit arg still overrides row value';
    is $m2, 1.0,        'explicit arg still overrides row value';
};

subtest 'apply_daily_decay advances one day at a time' => sub {
    my $dir   = tempdir(CLEANUP => 1);
    my $file  = "$dir/shed.json";
    my $model = shed_model($file);
    my $id    = make_item($model, decay_modifiers => $D)->getCol('id');

    # settling branch interpolates 1.00 -> 0.75 across days 2..5:
    #   day 2 progress 0/3 -> 1.0000 -> 20
    #   day 3 progress 1/3 -> 0.9167 -> 18
    #   day 4 progress 2/3 -> 0.8333 -> 16
    # fading branch starts at the settling multiplier:
    #   day 5            -> 0.7500 -> 15
    my %expected = (
        1 => ['fresh',    20],
        2 => ['settling', 20],
        3 => ['settling', 18],
        4 => ['settling', 16],
        5 => ['fading',   15],
    );

    for my $day (sort { $a <=> $b } keys %expected) {
        my ($decayed, $mult) = $model->get($id)->apply_daily_decay;
        my $item = $model->get($id);
        my ($want_cond, $want_val) = @{ $expected{$day} };

        is $item->getCol('days_in_shed'), $day,       "day $day: days_in_shed incremented";
        is $item->getCol('condition'),    $want_cond, "day $day: condition $want_cond";
        is $item->getCol('decayed_value'), $want_val, "day $day: decayed_value $want_val";
        cmp_ok $mult, '>', 0, "day $day: multiplier is positive";
    }
};

subtest 'estimated value range tracks decayed value' => sub {
    my $dir   = tempdir(CLEANUP => 1);
    my $file  = "$dir/shed.json";
    my $model = shed_model($file);
    my $id    = make_item($model, decay_modifiers => $D)->getCol('id');

    $model->get($id)->apply_daily_decay for 1 .. 5;
    my $item = $model->get($id);
    my $decayed = $item->getCol('decayed_value');
    my $min = $item->getCol('estimated_value_min');
    my $max = $item->getCol('estimated_value_max');

    is $min, int($decayed * 0.8), 'est_min is 80% of decayed_value';
    is $max, int($decayed * 1.2), 'est_max is 120% of decayed_value';
    cmp_ok $min, '<=', $max,      'est_min <= est_max';
    cmp_ok $min, '>',  0,         'est_min positive';
};

subtest 'decay is persisted to disk' => sub {
    my $dir   = tempdir(CLEANUP => 1);
    my $file  = "$dir/shed.json";
    my $model = shed_model($file);
    my $id    = make_item($model, decay_modifiers => $D)->getCol('id');

    $model->get($id)->apply_daily_decay for 1 .. 10;

    # A brand new model instance must see the aged state, otherwise the daily
    # tick is mutating a table that never reaches disk.
    my $reread = shed_model($file)->get($id);
    is $reread->getCol('days_in_shed'),  10,      'days_in_shed persisted across model instances';
    is $reread->getCol('condition'),     'fading', 'condition persisted';
    is $reread->getCol('decayed_value'),  8,       'decayed_value persisted';
};

subtest 'multiple items age independently in one batch' => sub {
    my $dir   = tempdir(CLEANUP => 1);
    my $file  = "$dir/shed.json";
    my $model = shed_model($file);

    my $a = make_item($model, decay_modifiers => $D, original_value => 20)->getCol('id');
    my $b = make_item($model, decay_modifiers => $D, original_value => 40)->getCol('id');
    my $c = make_item($model, decay_modifiers => $FAST, original_value => 20)->getCol('id');

    # Both D-items age twice; the FAST item ages once.
    $model->get($a)->apply_daily_decay;
    $model->get($b)->apply_daily_decay;
    $model->get($a)->apply_daily_decay;
    $model->get($b)->apply_daily_decay;
    $model->get($c)->apply_daily_decay;

    my $ra = $model->get($a);
    my $rb = $model->get($b);
    my $rc = $model->get($c);

    is $ra->getCol('days_in_shed'), 2, 'item a aged twice';
    is $rb->getCol('days_in_shed'), 2, 'item b aged twice';
    is $rc->getCol('days_in_shed'), 1, 'item c aged once (skipped batch 1)';

    is $ra->getCol('condition'), 'settling', 'item a settling at day 2 (default mods)';

    # FAST has settling_day => 1, so day 1 sits exactly on the boundary and
    # reads as settling with a full fresh multiplier.
    is $rc->getCol('condition'), 'settling', 'item c settling at day 1 (fast mods, settling_day 1)';
    is $rc->getCol('decayed_value'), 20,       'item c full value at day 1 boundary';
    cmp_ok $rb->getCol('decayed_value'), '>', $ra->getCol('decayed_value'),
        'higher original_value decays to a higher absolute value';
};

done_testing;