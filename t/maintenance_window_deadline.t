use v5.28;
use Modern::Perl;
use Test::More;
use Time::HiRes qw(time sleep);
use IO::Socket::INET;
use POSIX ();
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use Mojo::IOLoop;

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::Season;

my $acceptor;

END {
    kill('TERM', $acceptor) if defined $acceptor;
    waitpid($acceptor, 0)   if defined $acceptor;
}

my $data_dir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $data_dir;

my $svc_token = 'test-bot-token-abc123';
write_file("$data_dir/magic_mountain.yml", <<"YAML");
bots:
  count: 1
  profiles:
    - id: greed_desperate
bot_service_token: $svc_token
maintenance_bot_deadline_minutes: 0.05
YAML
$ENV{MM_CFG_FILE}       = "$data_dir/magic_mountain.yml";
$ENV{MM_SKIP_SEASON_CHECK} = 1;

MagicMountain::Model::Season->new(file => "$data_dir/seasons.json")
    ->create(
        id            => 's1',
        label         => 'Test Season',
        status        => 'active',
        day           => 3,
        length        => 30,
        faction_state => {},
    )->save;

my $accts = MagicMountain::Model::Account->new(file => "$data_dir/accounts.json");
my $bot_a = $accts->create(username => 'bot-greed_desperate-001');
$bot_a->save;

my $human_a = $accts->create(username => 'player');
$human_a->save;

my $chars = MagicMountain::Model::Character->new(file => "$data_dir/characters.json");
$chars->create(
    name              => 'bot-greed_desperate-001',
    account_id        => $bot_a->getCol('id'),
    season_id         => 's1',
    score             => 0,
    scrap             => 0,
    action_points     => 15,
    action_points_max => 15,
    is_bot            => 1,
    bot_profile_id    => 'greed_desperate',
    faction_sales     => {},
    standing          => {},
    faction_snubs     => {},
)->save;
$chars->create(
    name              => 'player',
    account_id        => $human_a->getCol('id'),
    season_id         => 's1',
    score             => 42,
    scrap             => 10,
    action_points     => 5,
    action_points_max => 15,
    is_bot            => 0,
)->save;

MagicMountain::Model::Account->new(file => "$data_dir/sessions.json")->save;

my $t   = TestEnv->create_app;
my $app = $t->app;
$app->config->{bot_service_token}                = $svc_token;
$app->config->{maintenance_bot_deadline_minutes} = 0.05;

# A TCP listener that accepts connections but never responds. The bot-turn
# subprocess connects to it and blocks forever, so its completion callback
# can never fire — the exact "lost subprocess signal" incident of 2026-09-08.
my $hang = IO::Socket::INET->new(
    Listen    => 5,
    LocalAddr => '127.0.0.1:0',
    ReuseAddr => 1,
    Proto     => 'tcp',
) or die "hang server: $!";
my $hang_port = $hang->sockport;

$acceptor = fork;
die "fork failed" unless defined $acceptor;
if ($acceptor == 0) {
    local $SIG{TERM} = sub { POSIX::_exit(0) };
    my @held;
    while (1) {
        my $c = $hang->accept or next;
        push @held, $c;
    }
}
$ENV{MOUNTAIN_DAEMON_URL} = "http://127.0.0.1:$hang_port";

my $maint     = $app->maintenance;
my $day_before = $app->seasons->get('s1')->getCol('day');

subtest 'bot window force-closes at deadline despite a wedged subprocess' => sub {
    my $start  = time;
    my $opened = $app->daily_maintenance->open_bot_window($maint);
    ok $opened, 'bot window opened through production entry point';
    ok $maint->bot_window_open, 'window is open immediately';

    # Drive the real Mojo event loop so the subprocess spawns and the deadline
    # timer runs. The subprocess never completes (hung on the listener), so
    # under the pre-fix code the window stays open forever and this hits the cap.
    my $end = $start + 20;
    while ($maint->bot_window_open && time < $end) {
        Mojo::IOLoop->one_tick;
        sleep 0.05;
    }
    my $elapsed = time - $start;

    ok !$maint->bot_window_open,
        'window force-closed by the deadline even with a wedged bot subprocess'
        or diag sprintf(
        'window still open after %.1fs cap — the pre-fix failure mode', $elapsed);

    ok $elapsed >= 2.5,
        sprintf('closed via the deadline timer (%.1fs), not a completion callback', $elapsed);

    $app->seasons->load;
    is $app->seasons->get('s1')->getCol('day'), $day_before + 1,
        'rollover ran — day advanced';
    ok !$maint->in_maintenance, 'in_maintenance cleared after force-close';
    my $opened_at = $maint->can('bot_window_opened_at') ? $maint->bot_window_opened_at : undef;
    is $opened_at, 0, 'opened_at reset after force-close';
};

done_testing;