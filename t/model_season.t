use Modern::Perl;

use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(read_file write_file);
use Mojo::JSON qw(encode_json decode_json);

use_ok('MagicMountain::Model::Season');

my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
write_file($file, '{}');

my $season = MagicMountain::Model::Season->new(file => $file);

subtest 'columns extend defaults with length, day, end_of_day_hour, status, faction_state' => sub {
    is_deeply(
        $season->columns,
        [qw{id updatedAt createdAt label length day end_of_day_hour status faction_state faction_climate crier_message crier_snapshot last_maintenance daily_modifiers personal_event_counts global_event_text}],
        'Season columns include all fields including faction_state and crier fields'
    );
};

subtest 'create - with createdAt override' => sub {
    my $obj = $season->create(createdAt => 12345);
    is($obj->row->{createdAt}, 12345, 'create sets provided createdAt');
};

subtest 'create - with season columns' => sub {
    my $obj = $season->create(length => 30, day => 1, end_of_day_hour => 22);
    is($obj->row->{length}, 30, 'create sets length');
    is($obj->row->{day}, 1, 'create sets day');
    is($obj->row->{end_of_day_hour}, 22, 'create sets end_of_day_hour');
};

subtest 'create - with status' => sub {
    my $obj = $season->create(status => 'active');
    is($obj->row->{status}, 'active', 'create sets status');
};

subtest 'getCol / setCol on season columns' => sub {
    my $obj = $season->create(length => 10, day => 5, end_of_day_hour => 18, status => 'active');
    is($obj->getCol('length'), 10, 'getCol returns length');
    is($obj->getCol('day'), 5, 'getCol returns day');
    is($obj->getCol('end_of_day_hour'), 18, 'getCol returns end_of_day_hour');
    is($obj->getCol('status'), 'active', 'getCol returns status');
    $obj->setCol('day', 6);
    is($obj->row->{day}, 6, 'setCol updates day');
    $obj->setCol('status', 'archived');
    is($obj->row->{status}, 'archived', 'setCol updates status');
};

done_testing;