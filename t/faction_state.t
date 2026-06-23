use Modern::Perl;
use Test::More;
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::Model::Season;
use MagicMountain::Model::ShedItem;
use MagicMountain::Activity::MarketVisit;

{
    package FakeDispositionStore;
    sub new { bless { items => [] }, shift }
    sub create {
        my ($self, %params) = @_;
        my $item = bless { %params }, 'FakeShedItem';
        push @{ $self->{items} }, $item;
        return $item;
    }
}

{
    package FakeApp;
    sub new { bless {}, shift }
    sub home { $FindBin::Bin . '/..' }
    sub log { bless {}, 'FakeLogger' }
    sub shed {
        my $self = shift;
        $self->{_shed_items} //= [];
        return $self;
    }
    sub create {
        my ($self, %params) = @_;
        my $item = bless { %params }, 'FakeShedItem';
        push @{ $self->{_shed_items} }, $item;
        return $item;
    }
    sub get {
        my ($self, $id) = @_;
        for my $item (@{ $self->{_shed_items} }) {
            return $item if $item->{id} && $item->{id} eq $id;
        }
        return;
    }
    sub delete {
        my ($self, $id) = @_;
        my @kept;
        for my $item (@{ $self->{_shed_items} }) {
            push @kept, $item unless $item->{id} && $item->{id} eq $id;
        }
        $self->{_shed_items} = \@kept;
    }
    sub transcript { bless {}, 'FakeTranscript' }
    sub disposition {
        my $self = shift;
        $self->{_disposition_store} //= FakeDispositionStore->new;
        return $self->{_disposition_store};
    }
    sub seasons { shift->{_seasons} }
    sub active_season { shift->{_active_season} }
    sub find {
        my ($self, $code) = @_;
        my @found;
        for my $item (@{ $self->{_shed_items} }) {
            push @found, $item if $code->($item);
        }
        return \@found;
    }
}
{
    package FakeLogger;
    sub debug { }
    sub info  { }
}
{
    package FakeShedItem;
    sub new { my $class = shift; bless { @_ }, $class }
    sub getCol { my ($self, $col) = @_; $self->{$col} }
    sub setCol { my ($self, $col, $val) = @_; $self->{$col} = $val }
    sub save { 1 }
    sub delete { 1 }
}
{
    package FakeTranscript;
    sub log_event { 1 }
}

subtest 'sale updates season faction_state' => sub {
    my $data_dir = tempdir(CLEANUP => 1);
    my $season_file = "$data_dir/seasons.json";

    my $season = MagicMountain::Model::Season->new(file => $season_file);
    $season->create(
        id     => 's1', label => 'Test', status => 'active',
        day    => 1, length => 30,
        faction_state => {},
    )->save;

    my $app = FakeApp->new;
    $app->{_seasons} = $season;
    $app->{_active_season} = $season;

    my $content_file = "$data_dir/factions.yml";
    write_file($content_file, <<'YAML');
factions:
  - id: syndicate
    name: "The Syndicate"
    interests: [thermal, power]
    base_multiplier: 1.1
YAML

    my $m = MagicMountain::Activity::MarketVisit->new(
        file             => "$data_dir/activities.json",
        app              => $app,
        content_filename => $content_file,
        log              => $app->log,
    );
    $m->load_content;

    my $char = bless {
        id            => 'char-1',
        action_points => 15,
        scrap         => 0,
        score         => 0,
    }, 'FakeShedItem';

    # Create a shed item and begin market visit
    $app->shed->create(
        id => 'item-1', char_id => 'char-1', artifact_id => 'thermal_box_001',
        behaviors => ['thermal', 'power'], decayed_value => 20, original_value => 20,
    );

    $m->dispatch($char, 'begin');
    $m->dispatch($char, 'offer', shed_item_id => 'item-1');

    # Verify season faction_state was updated
    $season->load;
    my $fs = $season->getCol('faction_state');
    ok($fs, 'faction_state exists');
    is($fs->{syndicate}{influence}, 26, 'influence = sold value (20 * 1.1 * 1.2 = 26)');
    is($fs->{syndicate}{artifacts_received}, 1, 'artifacts_received = 1');
    is($fs->{syndicate}{intake_by_trait}{thermal}, 1, 'thermal trait counted');
    is($fs->{syndicate}{intake_by_trait}{power}, 1, 'power trait counted');
};

done_testing;
