package MagicMountain::Controller::Game;
use Mojo::Base 'MagicMountain::Controller', '-signatures';
use Mojo::JSON qw(encode_json);

sub show ($self) {
    my $player_id = $self->current_player;

    my $account = $self->app->accounts->get($player_id);

    my $season = $self->app->active_season;

    my ($char_model) = @{ $self->app->characters->find(
        sub { $_[0]->{account_id} eq $player_id && (!$season || $_[0]->{season_id} eq $season->getCol('id')) }
    ) };

    unless ($char_model) {
        my $daily_ap = $self->app->config->{default_action_points} // 15;
        $char_model = $self->app->characters->create(
            name                  => $account->getCol('username'),
            account_id            => $player_id,
            season_id             => $season ? $season->getCol('id') : undef,
            score                 => 0,
            scrap                 => 0,
            action_points         => $season ? $daily_ap : 0,
            action_points_max     => $daily_ap,
            pending_activity_id   => undef,
        );
        $char_model->save;
    }

    my $row = $char_model->row;
    my $activity;
    my $prospecting_view;
    my $market_view;

    my $id = $row->{pending_activity_id};
    if ($id) {
        $self->app->prospecting->load;
        my $type = $self->app->prospecting->table->{$id}{type} // '';
        if ($type eq 'prospecting') {
            $activity = $self->app->prospecting->get($id);
            if ($activity && $activity->phase ne 'idle') {
                my $a = $activity->artifact;
                $prospecting_view = {
                    id     => $a->{id},
                    stage  => $a->{stage},
                    value  => $a->{value},
                    signal => $a->{signal},
                    intro  => $a->{intro},
                };
            }
        } elsif ($type eq 'market_visit') {
            $activity = $self->app->market->get($id);
            if ($activity && $activity->phase ne 'idle') {
                my $c = $activity->customer;
                $market_view = {
                    customer => {
                        faction_id   => $c->{faction_id},
                        faction_name => $c->{faction_name},
                        disposition  => $c->{disposition} // 'unknown',
                    },
                    irritation => $c->{irritation} // 0,
                };
            }
        }
    }

    my $skills = $self->app->skills_data;
    for my $s (@$skills) {
        $s->{current_level} = $char_model->getCol('skill_' . $s->{id}) // 0;
    }

    my $shed_items = [];
    if ($char_model) {
        my $items = $self->app->shed->find(
            sub { $_[0]->{char_id} eq $char_model->getCol('id') }
        );
        for my $item (@$items) {
            push @$shed_items, {
                id                   => $item->getCol('id'),
                artifact_id          => $item->getCol('artifact_id'),
                condition            => $item->getCol('condition'),
                days_in_shed         => $item->getCol('days_in_shed'),
                estimated_value_min  => $item->getCol('estimated_value_min'),
                estimated_value_max  => $item->getCol('estimated_value_max'),
            };
        }
    }

    $self->respond_to(
        json => sub {
            $self->render(json => {
                ok           => 1,
                player       => {
                    name              => $char_model->getCol('name'),
                    action_points     => $char_model->getCol('action_points'),
                    action_points_max => $char_model->getCol('action_points_max'),
                    scrap             => $char_model->getCol('scrap'),
                    score             => $char_model->getCol('score'),
                    faction_sales     => $char_model->getCol('faction_sales') // {},
                    skills            => {
                        map { $_->{id} => $_->{current_level} } @$skills
                    },
                },
                prospecting  => $prospecting_view,
                market_visit => $market_view,
                shed         => $shed_items,
                season       => {
                    day        => $season ? $season->getCol('day')     : 0,
                    total_days => $season ? $season->getCol('length')  : 0,
                },
            });
        },
        html => sub {
            $self->stash(
                player_name       => $account->getCol('username'),
                season_label      => $season ? ($season->getCol('label') // 'Season 1') : 'Upcoming',
                season_day        => $season ? ($season->getCol('day') // 1)             : '—',
                season_total_days => $season ? ($season->getCol('length') // 30)         : '—',
                season_is_active  => $season ? 1 : 0,
                score             => $row->{score} // 0,
                scrap             => $row->{scrap} // 0,
                action_points     => $row->{action_points} // 0,
                action_points_max => $row->{action_points_max} // 15,
                active_phase      => $activity ? $activity->phase : undef,
                artifact_json     => $prospecting_view ? encode_json($prospecting_view) : 'null',
            );
            $self->render('game/show');
        },
    );
}

1;
