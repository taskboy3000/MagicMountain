package MagicMountain::Controller::Factions;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $char = $self->_require_character or return;
    my $season = $self->app->active_season;
    return $self->rendered(204) unless $season;

    my $factions = $self->app->factions_data || [];
    my $standing = $char->getCol('standing') // {};
    my $sales    = $char->getCol('faction_sales') // {};
    my $fs       = $season->getCol('faction_state') // {};

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        my $dom   = $self->app->dominance_service;
        my $fc    = $season->faction_climate // {};
        my $tier  = $fc->{intensity} // 'contested';

        my $ranked = $dom->faction_positions($season);
        my $lowest = 1;
        for my $r (@$ranked) {
            $lowest = $r->{row_offset} if $r->{row_offset} > $lowest;
        }
        my $mountain_height = $lowest < 10 ? 10 : $lowest;
        if ($mountain_height != 22) {
            $ranked = $dom->faction_positions($season, $mountain_height);
            $lowest = 1;
            for my $r (@$ranked) {
                $lowest = $r->{row_offset} if $r->{row_offset} > $lowest;
            }
            $mountain_height = $lowest < 10 ? 10 : $lowest;
        }

        my %faction_lookup = map { $_->{id} => $_ } @$factions;
        my @display;
        for my $r (@$ranked) {
            my $f = $faction_lookup{$r->{faction_id}} or next;
            push @display, {
                %$r,
                name        => $f->{name},
                short_name  => $f->{short_name} // $f->{name},
                icon        => $f->{icon} ? $self->url_for('/images') . '/' . $f->{icon} : undef,
                disposition => $f->{disposition} // '',
            };
        }

        my $shape = $dom->_build_shape($mountain_height, 19);
        my $raster = $dom->_build_raster($tier, $shape);
        $self->stash(factions => \@display, faction_climate => $fc, mountain_raster => $raster, mountain_height => $mountain_height);
        return $self->render('factions/mountain_chart', layout => undef);
    }

    $self->render(json => {
        ok           => 1,
        factions     => $factions,
        standing     => $standing,
        faction_sales => $sales,
        faction_state => $fs,
    });
}

1;
