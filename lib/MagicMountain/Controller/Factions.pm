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
        my $ranked = $self->app->dominance_service->ranked_factions($season);
        my $fc     = $season->faction_climate // {};
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
        my $tier   = $fc->{intensity} // 'contested';
        my $raster = $self->app->dominance_service->_build_raster($tier);
        $self->stash(factions => \@display, faction_climate => $fc, mountain_raster => $raster);
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
