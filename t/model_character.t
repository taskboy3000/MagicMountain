use Modern::Perl;

use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(read_file write_file);
use Mojo::JSON qw(encode_json decode_json);

use_ok('MagicMountain::Model::Character');

my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
write_file($file, '{}');

my $char = MagicMountain::Model::Character->new(file => $file);

subtest 'columns extend defaults with character columns' => sub {
    is_deeply(
        $char->columns,
        [qw{id updatedAt createdAt name account_id season_id score scrap action_points action_points_max pending_activity_id faction_sales standing faction_snubs snub_day current_location current_view result skill_prospecting skill_upcycling skill_selling skill_smuggling loyalty_visits_since is_bot bot_profile_id seen_orientation settings_muted onboarding pending_notices turns_remaining smuggle_reroll_used}],
        'Character columns include all declared columns'
    );
};

subtest 'create - valid Character columns' => sub {
    my $obj = $char->create(
        name            => 'Merida',
        account_id      => 'acct-123',
        season_id       => 'season-1',
        score           => 42,
        scrap           => 10,
        action_points   => 7,
        action_points_max => 15,
    );
    is($obj->row->{name},            'Merida',    'create sets name');
    is($obj->row->{account_id},      'acct-123',  'create sets account_id');
    is($obj->row->{season_id},       'season-1',  'create sets season_id');
    is($obj->row->{score},           42,          'create sets score');
    is($obj->row->{scrap},           10,          'create sets scrap');
    is($obj->row->{action_points},   7,           'create sets action_points');
};

subtest 'getCol / setCol on subclass columns' => sub {
    my $obj = $char->create(name => 'Elinor', account_id => 'a1', season_id => 's1', score => 10, scrap => 5, action_points => 3, action_points_max => 15);
    is($obj->getCol('name'), 'Elinor', 'getCol returns name');
    is($obj->getCol('account_id'), 'a1', 'getCol returns account_id');
    is($obj->getCol('season_id'), 's1', 'getCol returns season_id');
    is($obj->getCol('score'), 10, 'getCol returns score');
    is($obj->getCol('scrap'), 5,  'getCol returns scrap');
    is($obj->getCol('action_points'), 3, 'getCol returns action_points');
    $obj->setCol('score', 99);
    is($obj->row->{score}, 99, 'setCol updates score');
    $obj->setCol('scrap', 50);
    is($obj->row->{scrap}, 50, 'setCol updates scrap');
};

done_testing;