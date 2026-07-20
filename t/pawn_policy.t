use Modern::Perl;
use Test2::V0;
use FindBin;
use lib ("$FindBin::Bin/../lib");
use MagicMountain::Bot::PawnPolicy;

subtest 'always policy offers every banned item' => sub {
    my $item  = { decayed_value => 5, banned => 1 };
    my $state = { consecutive_seizures => 0 };
    my $pol   = { name => 'always' };
    is MagicMountain::Bot::PawnPolicy::evaluate($item, $state, $pol), 'offer', 'always returns offer';
};

subtest 'value_threshold skips low-value items' => sub {
    my $item  = { decayed_value => 5 };
    my $state = {};
    my $pol   = { name => 'value_threshold', params => { min_value => 10 } };
    is MagicMountain::Bot::PawnPolicy::evaluate($item, $state, $pol), 'skip', 'item below threshold skipped';
};

subtest 'value_threshold offers items above threshold' => sub {
    my $item  = { decayed_value => 15 };
    my $state = {};
    my $pol   = { name => 'value_threshold', params => { min_value => 10 } };
    is MagicMountain::Bot::PawnPolicy::evaluate($item, $state, $pol), 'offer', 'item above threshold offered';
};

subtest 'stop_after_seizure stops after N seizures' => sub {
    my $item  = { decayed_value => 20 };
    my $state = { consecutive_seizures => 2 };
    my $pol   = { name => 'stop_after_seizure', params => { max_seizures => 2 } };
    is MagicMountain::Bot::PawnPolicy::evaluate($item, $state, $pol), 'stop', 'stops after max seizures';
};

subtest 'stop_after_seizure offers when under limit' => sub {
    my $item  = { decayed_value => 20 };
    my $state = { consecutive_seizures => 0 };
    my $pol   = { name => 'stop_after_seizure', params => { max_seizures => 2 } };
    is MagicMountain::Bot::PawnPolicy::evaluate($item, $state, $pol), 'offer', 'offers under seizure limit';
};

subtest 'default policy (no name) offers the item' => sub {
    my $item  = { decayed_value => 1 };
    my $state = {};
    my $pol   = {};
    is MagicMountain::Bot::PawnPolicy::evaluate($item, $state, $pol), 'offer', 'empty policy defaults to offer';
};

subtest 'composite_and requires all sub-policies to offer' => sub {
    my $item  = { decayed_value => 20 };
    my $state = {};
    my $pol   = {
        name   => 'composite_and',
        params => {
            policies => [
                { name => 'value_threshold', params => { min_value => 10 } },
                { name => 'always' },
            ],
        },
    };
    is MagicMountain::Bot::PawnPolicy::evaluate($item, $state, $pol), 'offer', 'composite_and offers when all pass';

    my $low_item = { decayed_value => 5 };
    is MagicMountain::Bot::PawnPolicy::evaluate($low_item, $state, $pol), 'skip', 'composite_and skips when one fails';
};

subtest 'composite_or offers if any sub-policy offers' => sub {
    my $item  = { decayed_value => 5 };
    my $state = {};
    my $pol   = {
        name   => 'composite_or',
        params => {
            policies => [
                { name => 'value_threshold', params => { min_value => 10 } },
                { name => 'always' },
            ],
        },
    };
    is MagicMountain::Bot::PawnPolicy::evaluate($item, $state, $pol), 'offer', 'composite_or offers when any passes';

    my $pol_skip = {
        name   => 'composite_or',
        params => {
            policies => [
                { name => 'value_threshold', params => { min_value => 10 } },
                { name => 'value_threshold', params => { min_value => 20 } },
            ],
        },
    };
    is MagicMountain::Bot::PawnPolicy::evaluate($item, $state, $pol_skip), 'skip', 'composite_or skips when none pass';
};

done_testing;
