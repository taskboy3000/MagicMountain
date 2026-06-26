use Modern::Perl;
use Test::More;
use FindBin;
use lib ("$FindBin::Bin/../lib");

use MagicMountain::SeasonReport;

my @all_factions = (
    { id => 'syndicate',        name => 'The Syndicate' },
    { id => 'faculty',          name => 'The Faculty' },
    { id => 'purifiers',        name => 'The Purifiers' },
    { id => 'libremount',       name => 'LibreMount' },
    { id => 'revelationists',   name => 'The Revelationists' },
);

subtest 'empty season — minimal sections' => sub {
    my $r = MagicMountain::SeasonReport->new(
        final_score => 0, final_scrap => 0, rank => 10,
        standing => {}, highlights => {},
        factions => \@all_factions,
        log => sub {},
    );
    my $sections = $r->build;
    my @ids = map { $_->{id} } @$sections;
    is_deeply \@ids, ['header', 'market', 'rank', 'closing'],
        'empty season: header, market (fragmented), rank, closing';
    is($sections->[1]{variant}, 'fragmented', 'market variant is fragmented when no faction data');
    is($sections->[2]{variant}, 'low', 'rank variant is low for rank 10');
};

subtest 'full season with dominant faction' => sub {
    my $r = MagicMountain::SeasonReport->new(
        final_score => 150, final_scrap => 75, rank => 1,
        standing => { syndicate => 4, faculty => 1 },
        highlights => {
            total_sales           => 14,
            top_sale_value        => 64,
            top_sale_faction      => 'syndicate',
            evolved_artifacts_sold => 2,
            clearance_bonus       => 25,
            top_faction           => 'syndicate',
            top_faction_influence => 495,
            factions_competing    => 5,
        },
        factions => \@all_factions,
        log => sub {},
    );
    my $sections = $r->build;
    my @ids = map { $_->{id} } @$sections;
    ok(grep { $_ eq 'market' } @ids, 'market section present');
    ok(grep { $_ eq 'agent_impact' } @ids, 'agent impact present');
    ok(grep { $_ eq 'total_sales' } @ids, 'total sales present');
    ok(grep { $_ eq 'best_sale' } @ids, 'best sale present');
    ok(grep { $_ eq 'evolved_artifacts' } @ids, 'evolved artifacts present');
    ok(grep { $_ eq 'clearance' } @ids, 'clearance present');
    ok(grep { $_ eq 'faction_event' } @ids, 'faction events present');

    my ($m) = grep { $_->{id} eq 'market' } @$sections;
    is($m->{variant}, 'dominated', 'market is dominated');
    is($m->{data}{top_faction}, 'The Syndicate', 'faction name resolved');

    my ($rsec) = grep { $_->{id} eq 'rank' } @$sections;
    is($rsec->{variant}, 'top', 'rank 1 is top variant');
};

subtest 'season with no standing data' => sub {
    my $r = MagicMountain::SeasonReport->new(
        final_score => 50, final_scrap => 10, rank => 5,
        standing => {}, highlights => { total_sales => 3 },
        factions => \@all_factions,
        log => sub {},
    );
    my $sections = $r->build;
    my @ids = map { $_->{id} } @$sections;
    ok(!grep { $_ eq 'agent_impact' } @ids, 'no agent impact without standing');
};

subtest 'season without evolved or clearance' => sub {
    my $r = MagicMountain::SeasonReport->new(
        final_score => 100, final_scrap => 20, rank => 3,
        standing => { syndicate => 2 },
        highlights => {
            total_sales     => 5,
            top_sale_value  => 30,
            top_sale_faction => 'faculty',
            evolved_artifacts_sold => 0,
            clearance_bonus => 0,
        },
        factions => \@all_factions,
        log => sub {},
    );
    my $sections = $r->build;
    my @ids = map { $_->{id} } @$sections;
    ok(!grep { $_ eq 'evolved_artifacts' } @ids, 'no evolved section when 0');
    ok(!grep { $_ eq 'clearance' } @ids, 'no clearance section when 0');
};

subtest 'log coderef called for each section' => sub {
    my @logged;
    my $r = MagicMountain::SeasonReport->new(
        final_score => 100, final_scrap => 20, rank => 2,
        standing => { syndicate => 3 },
        highlights => {
            total_sales     => 5,
            top_sale_value  => 30,
            top_sale_faction => 'syndicate',
            evolved_artifacts_sold => 1,
            clearance_bonus => 10,
            top_faction           => 'syndicate',
            top_faction_influence => 200,
            factions_competing    => 3,
        },
        factions => \@all_factions,
        log => sub { my ($event) = @_; push @logged, $event },
    );
    $r->build;
    ok(scalar @logged >= 6, 'at least 6 log events');
    my ($first) = grep { $_->{section} eq 'market' } @logged;
    ok($first, 'market section logged');
    is($first->{variant}, 'dominated', 'market variant logged');
};

done_testing;
