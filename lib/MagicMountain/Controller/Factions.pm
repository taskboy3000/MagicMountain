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

        $dom->ensure_mountain_data($season);
        $fc = $season->faction_climate;

        my $ranked = $fc->{mountain_positions} // [];
        my $mountain_height = $fc->{mountain_height} // 22;
        my $raster = $fc->{mountain_raster} // [];

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
