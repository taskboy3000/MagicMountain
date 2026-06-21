use Modern::Perl;
use Test::More;
use Mojo::JSON qw(encode_json);
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::Model::ShedItem;
use MagicMountain::Controller::Shed;

my $D = {
    fresh_multiplier    => 1.0,
    settling_multiplier => 0.75,
    fading_multiplier   => 0.40,
    settling_day        => 2,
    fading_day          => 5,
};

sub make_item {
    my ($class, %vals) = @_;
    my $item = $class->new(file => '/dev/null');
    $item->table->{x} = {};
    for my $k (keys %vals) {
        $item->setCol($k, $vals{$k});
    }
    return $item;
}

subtest '_item_view structure' => sub {
    my $item = make_item('MagicMountain::Model::ShedItem',
        id                  => 'i1',
        artifact_id         => 'thermal_box_001',
        condition           => 'settling',
        days_in_shed        => 3,
        original_value      => 20,
        estimated_value_min => 14,
        estimated_value_max => 18,
        behaviors           => ['thermal', 'power'],
        push_count          => 2,
        stage               => 'strained',
        has_evolved         => 0,
    );

    my $v = MagicMountain::Controller::Shed::_item_view($item);
    is $v->{id},                  'i1',              'id';
    is $v->{artifact_id},         'thermal_box_001',  'artifact_id';
    is $v->{condition},           'settling',         'condition';
    is $v->{days_in_shed},        3,                  'days_in_shed';
    is $v->{original_value},      20,                 'original_value';
    is $v->{estimated_value_min}, 14,                 'est_min';
    is $v->{estimated_value_max}, 18,                 'est_max';
    is_deeply $v->{behaviors},    ['thermal', 'power'], 'behaviors';
    is $v->{push_count},          2,                  'push_count';
    is $v->{stage},               'strained',         'stage';
    is $v->{has_evolved},         0,                  'has_evolved';

    ok !exists($v->{decayed_value}),  'decayed_value not leaked';
    ok !exists($v->{instability}),    'instability not leaked';
};

subtest 'filter by condition' => sub {
    my $items = [
        make_item('MagicMountain::Model::ShedItem', condition => 'fresh',    id => 'a'),
        make_item('MagicMountain::Model::ShedItem', condition => 'settling', id => 'b'),
        make_item('MagicMountain::Model::ShedItem', condition => 'fading',   id => 'c'),
        make_item('MagicMountain::Model::ShedItem', condition => 'fresh',    id => 'd'),
    ];

    my $filtered = MagicMountain::Controller::Shed::_apply_filters($items, bless {
        _params => { condition => 'fresh' }
    }, 'FakeC');

    is scalar @$filtered, 2, 'filtered to 2 fresh items';
    is $filtered->[0]->getCol('id'), 'a', 'first fresh item';
    is $filtered->[1]->getCol('id'), 'd', 'second fresh item';
};

subtest 'filter by artifact_id' => sub {
    my $items = [
        make_item('MagicMountain::Model::ShedItem', artifact_id => 'thermal_box_001', id => 'a'),
        make_item('MagicMountain::Model::ShedItem', artifact_id => 'void_core_001',   id => 'b'),
        make_item('MagicMountain::Model::ShedItem', artifact_id => 'thermal_box_001', id => 'c'),
    ];

    my $filtered = MagicMountain::Controller::Shed::_apply_filters($items, bless {
        _params => { artifact_id => 'thermal_box_001' }
    }, 'FakeC');

    is scalar @$filtered, 2, 'filtered to 2 thermal box items';
};

subtest 'filter by behavior' => sub {
    my $items = [
        make_item('MagicMountain::Model::ShedItem', behaviors => ['thermal', 'power'], id => 'a'),
        make_item('MagicMountain::Model::ShedItem', behaviors => ['field'],           id => 'b'),
        make_item('MagicMountain::Model::ShedItem', behaviors => ['thermal'],          id => 'c'),
    ];

    my $filtered = MagicMountain::Controller::Shed::_apply_filters($items, bless {
        _params => { behavior => 'thermal' }
    }, 'FakeC');

    is scalar @$filtered, 2, 'filtered to 2 thermal items';
};

subtest 'filter by value range' => sub {
    my $items = [
        make_item('MagicMountain::Model::ShedItem', estimated_value_min => 10, estimated_value_max => 20, id => 'a'),
        make_item('MagicMountain::Model::ShedItem', estimated_value_min => 15, estimated_value_max => 25, id => 'b'),
        make_item('MagicMountain::Model::ShedItem', estimated_value_min =>  5, estimated_value_max => 15, id => 'c'),
    ];

    my $filtered = MagicMountain::Controller::Shed::_apply_filters($items, bless {
        _params => { min_value => 10, max_value => 30 }
    }, 'FakeC');

    is scalar @$filtered, 2, 'filtered to items min>=10 and max<=30';
};

subtest 'sort and order' => sub {
    my $items = [
        make_item('MagicMountain::Model::ShedItem', estimated_value_min => 30, id => 'a'),
        make_item('MagicMountain::Model::ShedItem', estimated_value_min => 10, id => 'b'),
        make_item('MagicMountain::Model::ShedItem', estimated_value_min => 20, id => 'c'),
    ];

    my $desc = MagicMountain::Controller::Shed::_apply_filters($items, bless {
        _params => { sort => 'value', order => 'desc' }
    }, 'FakeC');
    is $desc->[0]->getCol('id'), 'a', 'desc: highest first';
    is $desc->[2]->getCol('id'), 'b', 'desc: lowest last';

    my $asc = MagicMountain::Controller::Shed::_apply_filters($items, bless {
        _params => { sort => 'value', order => 'asc' }
    }, 'FakeC');
    is $asc->[0]->getCol('id'), 'b', 'asc: lowest first';
    is $asc->[2]->getCol('id'), 'a', 'asc: highest last';
};

subtest 'no filters returns all' => sub {
    my $items = [
        make_item('MagicMountain::Model::ShedItem', condition => 'fresh',    id => 'a'),
        make_item('MagicMountain::Model::ShedItem', condition => 'settling', id => 'b'),
    ];

    my $filtered = MagicMountain::Controller::Shed::_apply_filters($items, bless {
        _params => {}
    }, 'FakeC');

    is scalar @$filtered, 2, 'no filters: all items returned';
};

{
    package FakeC;
    sub param {
        my ($self, $name) = @_;
        return $self->{_params}{$name};
    }
    1;
}

done_testing;
