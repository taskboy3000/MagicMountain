use Modern::Perl;
use Test2::V0;
use FindBin;
use lib ("$FindBin::Bin/../lib");
use MagicMountain::Bot::SellPolicy;

subtest 'should_stand_pat with stand_pat_resolve => [high]' => sub {
    my $policy = {
        name   => 'value_loyalist',
        params => { stand_pat_resolve => [qw(high)] },
    };
    ok  MagicMountain::Bot::SellPolicy::should_stand_pat('high',   $policy), 'high resolve accepted';
    ok !MagicMountain::Bot::SellPolicy::should_stand_pat('medium', $policy), 'medium resolve rejected';
    ok !MagicMountain::Bot::SellPolicy::should_stand_pat('low',    $policy), 'low resolve rejected';
};

subtest 'should_stand_pat with stand_pat_resolve => [high, medium]' => sub {
    my $policy = {
        name   => 'value_loyalist',
        params => { stand_pat_resolve => [qw(high medium)] },
    };
    ok  MagicMountain::Bot::SellPolicy::should_stand_pat('high',   $policy), 'high resolve accepted';
    ok  MagicMountain::Bot::SellPolicy::should_stand_pat('medium', $policy), 'medium resolve accepted';
    ok !MagicMountain::Bot::SellPolicy::should_stand_pat('low',    $policy), 'low resolve rejected';
};

subtest 'should_stand_pat default profile (no stand_pat_resolve)' => sub {
    my $policy = {
        name   => 'default',
        params => {},
    };
    ok !MagicMountain::Bot::SellPolicy::should_stand_pat('high',   $policy), 'high resolve default false';
    ok !MagicMountain::Bot::SellPolicy::should_stand_pat('medium', $policy), 'medium resolve default false';
    ok !MagicMountain::Bot::SellPolicy::should_stand_pat('low',    $policy), 'low resolve default false';
};

done_testing;
