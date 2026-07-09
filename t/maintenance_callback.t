use Modern::Perl;
use Test::More;
use Test::Mojo;
use Mojo::JSON qw(decode_json);
use File::Temp qw(tempdir);
use File::Slurp qw(read_file);
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::ShedItem;
use MagicMountain::Model::Season;

my $dataDir = tempdir(CLEANUP => 1);
$ENV{MM_DATA_DIR} = $dataDir;

subtest 'maintenance callback fires all 8 steps' => sub {
    MagicMountain::Model::Season->new(file => "$dataDir/seasons.json")
        ->create(
            id            => 's1',
            label         => 'Test Season',
            status        => 'active',
            day           => 3,
            length        => 30,
            faction_state => {
                syndicate => {
                    influence          => 42,
                    artifacts_received => 3,
                    intake_by_trait    => { thermal => 2, power => 1 },
                    daily_intake       => 2,
                    days_since_purchase => 1,
                    name               => 'The Syndicate',
                },
            },
            crier_message   => '',
            crier_snapshot   => undef,
        )->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dataDir/accounts.json");
    my $a = $accts->create(username => 'player');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dataDir/characters.json");
    my $char  = $chars->create(
        name              => 'player',
        account_id        => $a->getCol('id'),
        season_id         => 's1',
        score             => 42,
        scrap             => 10,
        action_points     => 5,
        action_points_max => 15,
    );
    $char->save;

    my $shed = MagicMountain::Model::ShedItem->new(file => "$dataDir/shed.json");
    $shed->create(
        id                  => 'sh1',
        char_id             => $char->getCol('id'),
        artifact_id         => 'thermal_box_001',
        condition           => 'fresh',
        days_in_shed        => 0,
        original_value      => 20,
        decayed_value       => 20,
        estimated_value_min => 16,
        estimated_value_max => 24,
        decay_modifiers     => {
            fresh_multiplier    => 1.0,
            settling_multiplier => 0.75,
            fading_multiplier   => 0.40,
            settling_day        => 2,
            fading_day          => 5,
        },
    )->save;

    # Initialize empty files for models the app helpers will access
    MagicMountain::Model::Account->new(file => "$dataDir/sessions.json")->save;

    my $t = Test::Mojo->new('MagicMountain');

    my $app    = $t->app;
    my $maint  = $app->maintenance;
    my $season = $app->seasons->get('s1');

    $maint->on_maintenance->($maint);

    # Reload season — the callback mutated and saved a different model instance
    $season = $app->seasons->get('s1');

    # 1. day advanced
    is $season->getCol('day'), 4, 'day advanced from 3 to 4';

    # 2. AP reset
    $app->characters->load;
    my $reloaded = $app->characters->get($char->getCol('id'));
    is $reloaded->getCol('action_points'), 15, 'AP reset to max';

    # 3. shed decay
    $app->shed->load;
    my $item = $app->shed->get('sh1');
    ok $item, 'shed item still exists';
    is $item->getCol('days_in_shed'), 1, 'days_in_shed incremented';
    is $item->getCol('condition'),    'fresh', 'still fresh at day 1';

    # 4. crier message set
    my $msg = $season->getCol('crier_message');
    ok length($msg // ''), 'crier_message populated';

    # 5. faction snapshots created
    $app->faction_snapshots->load;
    my $snaps = $app->faction_snapshots->find(
        sub { $_[0]->{season_id} eq 's1' }
    );
    cmp_ok scalar(@$snaps), '>=', 1, 'at least one faction snapshot created';
    my $snap = $snaps->[0];
    is $snap->getCol('day'),               4,           'snapshot day is 4';
    is $snap->getCol('faction_id'),        'syndicate', 'faction_id correct';
    is $snap->getCol('influence'),         42,          'influence captured';
    is $snap->getCol('artifacts_received'), 3,           'artifacts_received captured';

    # 6. faction daily state reset
    my $fs = $season->getCol('faction_state');
    ok $fs && $fs->{syndicate}, 'faction_state present';
    is $fs->{syndicate}{daily_intake},       0, 'daily_intake reset to 0';
    is $fs->{syndicate}{days_since_purchase}, 2, 'days_since_purchase incremented';

    # 7. transcript event logged
    my $transcript = $app->transcript;
    my $events     = $transcript->all_events;
    my $found = 0;
    for my $e (@$events) {
        if (($e->{type} // '') eq 'faction_snapshot') {
            $found = 1;
            last;
        }
    }
    ok $found, 'faction_snapshot event in transcript';

    # 8. last_maintenance updated
    cmp_ok $season->getCol('last_maintenance'), '>', 0, 'last_maintenance timestamp set';
};

subtest 'season ends automatically when day exceeds length' => sub {
    my $dir = tempdir(CLEANUP => 1);
    local $ENV{MM_DATA_DIR} = $dir;

    MagicMountain::Model::Season->new(file => "$dir/seasons.json")
        ->create(
            id      => 's1',
            label   => 'Expiring Season',
            status  => 'active',
            day     => 31,
            length  => 30,
            faction_state => {
                syndicate => { influence => 50, artifacts_received => 5, intake_by_trait => {}, daily_intake => 0, days_since_purchase => 0, name => 'Syndicate' },
            },
        )->save;

    my $accts = MagicMountain::Model::Account->new(file => "$dir/accounts.json");
    my $a = $accts->create(username => 'player');
    $a->save;

    my $chars = MagicMountain::Model::Character->new(file => "$dir/characters.json");
    my $char = $chars->create(name => 'player', account_id => $a->getCol('id'), season_id => 's1', score => 50, scrap => 10, action_points => 5, action_points_max => 15);
    $char->save;

    my $shed = MagicMountain::Model::ShedItem->new(file => "$dir/shed.json");
    my $shed_item = $shed->create(id => 'sh1', char_id => $char->getCol('id'), artifact_id => 'test', original_value => 10, decayed_value => 10, condition => 'fresh', days_in_shed => 0, estimated_value_min => 8, estimated_value_max => 12);
    $shed_item->save;

    MagicMountain::Model::Account->new(file => "$dir/sessions.json")->save;

    my $t = Test::Mojo->new('MagicMountain');
    my $maint = $t->app->maintenance;

    $maint->on_maintenance->($maint);

    my $season = $t->app->seasons->get('s1');
    is($season->getCol('status'), 'archived', 'season archived after day exceeds length');

    my $active = $t->app->active_season;
    is($active, undef, 'no active season after finalize');

    $t->app->season_records->load;
    my $records = $t->app->season_records->find(sub { $_[0]->{season_id} eq 's1' });
    is(scalar @$records, 1, 'season record created for player');

    $t->app->characters->load;
    my $remaining = $t->app->characters->find(sub { $_[0]->{season_id} eq 's1' });
    is(scalar @$remaining, 0, 'characters cleaned up');
};

done_testing;
