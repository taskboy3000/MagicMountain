package MagicMountain::Controller::Account;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub show ($self) {
    my $player_id = $self->current_player;
    return $self->rendered(204) unless $player_id;

    my $factions = $self->app->factions_data // [];
    my %name_of = map { $_->{id} => $_->{name} } @$factions;

    $self->app->season_records->load;
    $self->app->seasons->load;

    my $active_season = $self->app->active_season;
    my $all = $self->app->seasons->all;
    my @seasons = sort { ($b->{createdAt} // 0) <=> ($a->{createdAt} // 0) } values %$all;

    my @archive;
    for my $s (@seasons) {
        next unless $player_id;
        if ($s->{status} eq 'active') {
            $self->app->characters->load;
            my ($char) = @{ $self->app->characters->find(sub {
                $_[0]->{account_id} eq $player_id && $_[0]->{season_id} eq $s->{id}
            }) };
            push @archive, {
                id     => $s->{id},
                label  => $s->{label} // '?',
                status => 'active',
                day    => $s->{day} // 1,
                length => $s->{length} // 30,
                final_score => $char ? ($char->getCol('score') // 0) : 0,
            };
        } else {
            my $recs = $self->app->season_records->find(
                sub { $_[0]->{player_id} eq $player_id && $_[0]->{season_id} eq $s->{id} }
            );
            next unless @$recs;
            my $r = $recs->[0];
            my $highlights = $r->getCol('story_highlights') // {};
            push @archive, {
                id            => $s->{id},
                label         => $s->{label} // '?',
                status        => 'complete',
                final_score   => $r->getCol('final_score'),
                final_scrap   => $r->getCol('final_scrap'),
                rank          => $r->getCol('rank'),
                total_sales   => $highlights->{total_sales} // 0,
                top_sale      => sprintf("%d to %s", $highlights->{top_sale_value} // 0,
                    $name_of{$highlights->{top_sale_faction}} // $highlights->{top_sale_faction} // '?'),
            };
        }
    }

    my @actions = (
        { label => 'LOGOUT', attrs => { 'data-action-url' => $self->url_for('logout_api'), 'data-method' => 'DELETE', id => 'logout-btn', class => 'mm-btn', 'data-redirect' => $self->url_for('game') } },
    );

    my $account = $self->app->accounts->get($player_id);
    my $player_name = $account ? $account->getCol('username') : 'Unknown';

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(
            actions        => \@actions,
            archive        => \@archive,
            player_name    => $player_name,
            leaderboard_url => $self->url_for('leaderboard')->query(_format => 'fragment'),
        );
        return $self->render('account/settings', layout => undef);
    }

    $self->render(json => { ok => 1, _self => { actions => \@actions }, archive => \@archive });
}

1;
