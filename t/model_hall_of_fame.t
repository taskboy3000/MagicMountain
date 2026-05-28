use Modern::Perl;

use FindBin;
use lib ("$FindBin::Bin/../lib");

use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(read_file write_file);
use Mojo::JSON qw(encode_json decode_json);

use_ok('MagicMountain::Model::HallOfFame');

my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
write_file($file, '{}');

my $hof = MagicMountain::Model::HallOfFame->new(file => $file);

subtest 'columns extend defaults with character_name, score, season_id' => sub {
    is_deeply(
        $hof->columns,
        [qw{id updatedAt createdAt character_name score season_id}],
        'HallOfFame columns include character_name, score, season_id'
    );
};

subtest 'create - valid HallOfFame columns' => sub {
    my $obj = $hof->create(character_name => 'Merida', score => 100, season_id => 's1');
    is($obj->row->{character_name}, 'Merida', 'create sets character_name');
    is($obj->row->{score}, 100, 'create sets score');
    is($obj->row->{season_id}, 's1', 'create sets season_id');
};

subtest 'getCol / setCol on subclass columns' => sub {
    my $obj = $hof->create(character_name => 'Elinor', score => 50, season_id => 's2');
    is($obj->getCol('character_name'), 'Elinor', 'getCol returns character_name');
    is($obj->getCol('score'), 50, 'getCol returns score');
    is($obj->getCol('season_id'), 's2', 'getCol returns season_id');
    $obj->setCol('score', 75);
    is($obj->row->{score}, 75, 'setCol updates score');
};

done_testing;