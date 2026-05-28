use Modern::Perl;

use FindBin;
use lib ("$FindBin::Bin/../lib");

use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(read_file write_file);
use Mojo::JSON qw(encode_json decode_json);

use_ok('MagicMountain::Model::Character');

my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
write_file($file, '{}');

my $char = MagicMountain::Model::Character->new(file => $file);

subtest 'columns extend defaults with name, account_id, season_id, score' => sub {
    is_deeply(
        $char->columns,
        [qw{id updatedAt createdAt name account_id season_id score}],
        'Character columns include name, account_id, season_id, score'
    );
};

subtest 'create - valid Character columns' => sub {
    my $obj = $char->create(
        name       => 'Merida',
        account_id => 'acct-123',
        season_id  => 'season-1',
        score      => 42,
    );
    is($obj->row->{name}, 'Merida', 'create sets name');
    is($obj->row->{account_id}, 'acct-123', 'create sets account_id');
    is($obj->row->{season_id}, 'season-1', 'create sets season_id');
    is($obj->row->{score}, 42, 'create sets score');
};

subtest 'getCol / setCol on subclass columns' => sub {
    my $obj = $char->create(name => 'Elinor', account_id => 'a1', season_id => 's1', score => 10);
    is($obj->getCol('name'), 'Elinor', 'getCol returns name');
    is($obj->getCol('account_id'), 'a1', 'getCol returns account_id');
    is($obj->getCol('season_id'), 's1', 'getCol returns season_id');
    is($obj->getCol('score'), 10, 'getCol returns score');
    $obj->setCol('score', 99);
    is($obj->row->{score}, 99, 'setCol updates score');
};

done_testing;