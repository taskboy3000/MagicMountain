use Modern::Perl;

use FindBin;
use lib ("$FindBin::Bin/../lib");

use Test::More;
use File::Temp qw(tempfile);
use File::Slurp qw(read_file write_file);
use Mojo::JSON qw(encode_json decode_json);
use UUID::Tiny qw(:std);

use_ok('MagicMountain::Model::Account');

my ($fh, $file) = tempfile(SUFFIX => '.json', UNLINK => 1);
write_file($file, '{}');

my $acct = MagicMountain::Model::Account->new(file => $file);

subtest 'columns extend defaults with username and password' => sub {
    is_deeply(
        $acct->columns,
        [qw{id updatedAt createdAt username password}],
        'Account columns include username and password'
    );
};

subtest 'create - valid Account columns' => sub {
    my $obj = $acct->create(username => 'alice', password => 'secret');
    is($obj->getCol('username'), 'alice', 'create sets username');
    is($obj->getCol('password'), 'secret', 'create sets password');
};

subtest 'getCol / setCol on subclass columns' => sub {
    my $obj = $acct->create(username => 'carol', password => 'pass123');
    $obj->save;
    is($obj->getCol('username'), 'carol', 'getCol returns username');
    is($obj->getCol('password'), 'pass123', 'getCol returns password');
    $obj->setCol('username', 'carol2');
    is($obj->getCol('username'), 'carol2', 'setCol updates username');
};



done_testing;