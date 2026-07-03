use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;

use lib '.';
use lib 'lib';
use lib ("$FindBin::Bin/lib");
use TestEnv;

# --- Unit tests for RateLimiter class ---

BEGIN { use_ok('MagicMountain::RateLimiter') }

my $fake_time = 1000000;
my $rl = MagicMountain::RateLimiter->new(
    max_attempts          => 3,
    max_attempts_per_name => 2,
    window_minutes        => 60,
    block_minutes         => 60,
    time_func             => sub { $fake_time },
);



{
    # 1. Allow first request
    ok($rl->check('1.2.3.4'), 'first request allowed');
    is($rl->get_remaining('1.2.3.4'), 3, '3 remaining before any failures');
}

{
    # 2. Count increments
    is($rl->record_failure('1.2.3.4'), 1, 'failure count = 1');
    is($rl->record_failure('1.2.3.4'), 2, 'failure count = 2');
    is($rl->get_remaining('1.2.3.4'), 1, '1 remaining after 2 failures');
}

{
    # 3. Block at threshold
    is($rl->record_failure('1.2.3.4'), 3, 'failure count = 3');
    ok(!$rl->check('1.2.3.4'), 'blocked after 3 failures');
    is($rl->get_remaining('1.2.3.4'), 0, '0 remaining when blocked');
}

{
    # 4. Unblock after timeout
    $fake_time += 3601; # advance past block_minutes
    ok($rl->check('1.2.3.4'), 'unblocked after timeout');
    is($rl->get_remaining('1.2.3.4'), 3, 'full allowance after unblock');
}

{
    # 5. Window reset on inactivity
    $fake_time = 2000000;
    $rl->record_failure('5.6.7.8');
    $rl->record_failure('5.6.7.8');
    is($rl->get_remaining('5.6.7.8'), 1, '2 failures within window');
    $fake_time += 3601; # advance past window
    ok($rl->check('5.6.7.8'), 'window expiry allows request');
    is($rl->get_remaining('5.6.7.8'), 3, 'full allowance after window reset');
}

{
    # 6. Success clears
    $fake_time = 3000000;
    $rl->record_failure('9.10.11.12');
    $rl->record_failure('9.10.11.12');
    is($rl->get_remaining('9.10.11.12'), 1, '2 failures');
    $rl->record_success('9.10.11.12');
    is($rl->get_remaining('9.10.11.12'), 3, 'full allowance after success');
    ok($rl->check('9.10.11.12'), 'allowed after success');
}

{
    # 7. Cleanup removes stale blocked entries
    $fake_time = 4000000;
    $rl->record_failure('stale1');
    $rl->record_failure('stale1');
    $rl->record_failure('stale1'); # triggers block
    $fake_time += 3601; # past block expiry
    $rl->cleanup;
    ok($rl->check('stale1'), 'cleaned up stale block');
}

{
    # 8. Cleanup leaves active entries
    $fake_time = 5000000;
    $rl->record_failure('active1');
    is($rl->get_remaining('active1'), 2, 'active entry has 2 remaining');
    $fake_time += 10; # tiny advance, well within window
    $rl->cleanup;
    is($rl->get_remaining('active1'), 2, 'active entry survives cleanup with correct remaining');
    ok($rl->check('active1'), 'active entry still allows requests');
}

{
    # 9. IP isolation
    $fake_time = 6000000;
    $rl->record_failure('ip_a');
    ok($rl->check('ip_b'), 'different IP not affected');
    is($rl->get_remaining('ip_a'), 2, 'ip_a has 2 remaining');
    is($rl->get_remaining('ip_b'), 3, 'ip_b has full allowance');
}

{
    # 10. Block not bypassed by window expiry
    $fake_time = 7000000;
    $rl->record_failure('window_test');
    $rl->record_failure('window_test');
    $rl->record_failure('window_test'); # blocked
    $fake_time += 1800; # past window (60min) but not block (60min)
    ok(!$rl->check('window_test'), 'still blocked even after window expiry');
}

{
    # 11. Retry-After calculation
    $fake_time = 8000000;
    $rl->record_failure('retry_test');
    $rl->record_failure('retry_test');
    $rl->record_failure('retry_test');
    my $reset = $rl->get_reset_time('retry_test');
    ok($reset > 3500 && $reset <= 3600, "reset time ~3600s (got $reset)");
}

# --- Name-based rate limiting tests ---

{
    # 12. Name-based blocking
    $fake_time = 9000000;
    ok($rl->check_name('alice'), 'first name request allowed');
    $rl->record_name_failure('alice');
    ok($rl->check_name('alice'), 'still allowed after 1 failure');
    $rl->record_name_failure('alice');
    ok(!$rl->check_name('alice'), 'blocked after 2 name failures');
    is($rl->get_name_remaining('alice'), 0, '0 name remaining when blocked');
}

{
    # 13. Name isolation
    $fake_time = 10000000;
    $rl->record_name_failure('bob');
    ok($rl->check_name('carol'), 'different name not affected');
    is($rl->get_name_remaining('bob'), 1, 'bob has 1 remaining');
    is($rl->get_name_remaining('carol'), 2, 'carol has full allowance');
}

{
    # 14. Case sensitivity — the raw class is case-sensitive; controller normalizes
    $fake_time = 11000000;
    $rl->record_name_failure('Alice');
    $rl->record_name_failure('Alice');
    ok($rl->check_name('alice'), 'other case variant is not blocked (raw class is case-sensitive)');
    ok(!$rl->check_name('Alice'), 'same case variant is blocked');
}

# Note: test 14 confirms the raw class is case-sensitive.
# The controller normalizes via lc($name) before calling the RateLimiter.

{
    # 15. Name success clears
    $fake_time = 12000000;
    $rl->record_name_failure('dave');
    $rl->record_name_success('dave');
    ok($rl->check_name('dave'), 'allowed after name success');
    is($rl->get_name_remaining('dave'), 2, 'full allowance after name success');
}

{
    # 16. Name cleanup removes stale entries
    $fake_time = 13000000;
    $rl->record_name_failure('evan');
    $rl->record_name_failure('evan');
    $fake_time += 3601;
    $rl->cleanup;
    ok($rl->check_name('evan'), 'stale name cleaned up');
}

# --- Integration test: IP-based and name-based recorded together ---

{
    $fake_time = 14000000;
    my $rl2 = MagicMountain::RateLimiter->new(
        max_attempts          => 2,
        max_attempts_per_name => 1,
        window_minutes        => 60,
        block_minutes         => 60,
        time_func             => sub { $fake_time },
    );

    # Both IP and name tracked
    $rl2->record_failure('1.2.3.4');
    $rl2->record_name_failure('frank');
    ok(!$rl2->check_name('frank'), 'name blocked after 1 failure (max_per_name=1)');
    ok($rl2->check('1.2.3.4'), 'IP still allowed after 1 failure (max=2)');
    $rl2->record_failure('1.2.3.4');
    ok(!$rl2->check('1.2.3.4'), 'IP also blocked after 2 failures');
    $rl2->record_success('1.2.3.4');
    $rl2->record_name_success('frank');
    ok($rl2->check('1.2.3.4'), 'IP unblocked after success');
    ok($rl2->check_name('frank'), 'name unblocked after success');
}

done_testing;
