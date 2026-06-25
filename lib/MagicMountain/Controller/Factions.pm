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

    my $max_stars = $self->app->config->{faction_max_stars} // 5;
    my $top_sales = 0;
    $top_sales = $_ > $top_sales ? $_ : $top_sales for values %$sales;

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        my $is_secondary = ($self->param('panel') || '') eq 'secondary';
        my @display;
        for my $f (@$factions) {
            my $fid  = $f->{id};
            my $sale = $sales->{$fid} // 0;
            my $star_count = $top_sales > 0 ? int(($sale / $top_sales) * $max_stars) : 0;
            push @display, {
                %$f,
                icon              => $f->{icon} ? '/images/' . $f->{icon} : undef,
                display_name      => $is_secondary ? ($f->{short_name} // $f->{name}) : $f->{name},
                display_name_full => $f->{name},
                stars_display     => ('★' x $star_count) . ('☆' x ($max_stars - $star_count)),
                sales             => $sale,
            };
        }
        @display = sort { $b->{sales} <=> $a->{sales} } @display;
        $self->stash(factions => \@display);
        return $self->render('factions/registry', layout => undef);
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
