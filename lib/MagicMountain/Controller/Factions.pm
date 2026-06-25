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
        my $is_secondary = ($self->param('panel') || '') eq 'secondary';
        my @display;
        for my $f (@$factions) {
            push @display, {
                %$f,
                display_name      => $is_secondary ? ($f->{short_name} // $f->{name}) : $f->{name},
                display_name_full => $f->{name},
            };
        }
        $self->stash(
            factions      => \@display,
            standing      => $standing,
            faction_sales => $sales,
            faction_state => $fs,
        );
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
