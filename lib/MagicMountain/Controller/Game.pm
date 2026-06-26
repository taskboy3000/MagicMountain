package MagicMountain::Controller::Game;
use Mojo::Base 'MagicMountain::Controller', '-signatures';
use Mojo::JSON qw(encode_json);
use YAML::XS qw(LoadFile);

sub show ($self) {
    my $player_id = $self->current_player;

    # Handle unauthenticated users — render device frame with login form
    if (!$player_id) {
        $self->respond_to(
            json => sub { $self->render(json => { ok => 0, error => 'Not logged in' }, status => 401) },
            html => sub {
                $self->stash(authenticated => 0, player_name => '—', node_number => '—', unit_status => '');
                $self->render('game/show');
            },
        );
        return;
    }

    my $account = $self->app->accounts->get($player_id);
    $self->app->session_store->load;
    my $sess = $self->app->session_store->find_by_player_id($player_id);
    my $node_number = $sess ? $sess->getCol('node_number') // '07' : '07';

    my $season = $self->app->active_season;

    my $season_recap;

    if (!$season) {
        $self->app->season_records->load;
        my $archived = $self->app->seasons->find(sub { ($_[0]->{status} // '') eq 'archived' });
        if (@$archived) {
            my @sorted = sort { ($b->getCol('day') // 0) <=> ($a->getCol('day') // 0) } @$archived;
            my $last = $sorted[0];
            my $recs = $self->app->season_records->find(sub { $_[0]->{player_id} eq $player_id && $_[0]->{season_id} eq $last->getCol('id') });
            if (@$recs) {
                $season_recap = {
                    label         => $last->getCol('label'),
                    final_score   => $recs->[0]->getCol('final_score'),
                    final_scrap   => $recs->[0]->getCol('final_scrap'),
                    rank          => $recs->[0]->getCol('rank'),
                    standing      => $recs->[0]->getCol('faction_standing_snapshot'),
                    skills        => $recs->[0]->getCol('skills_snapshot'),
                    highlights    => $recs->[0]->getCol('story_highlights'),
                };
            }
        }

        # Auto-create new season
        my $prefix = $self->app->config->{default_season_label_prefix} // 'Season';
        my $max_num = 0;
        my $all = $self->app->seasons->all;
        my $re = qr/^\Q$prefix\E\s+(\d+)$/;
        for my $id (keys %$all) {
            my $row = $all->{$id};
            if ($row->{label} =~ $re) {
                my $n = $1;
                $max_num = $n if $n > $max_num;
            }
        }
        my $label = "$prefix " . ($max_num + 1);
        my $length = $self->app->config->{default_season_length} // 30;
        my $eod_hour = $self->app->config->{end_of_day_hour} // 0;

        $season = $self->app->seasons->create(
            label           => $label,
            length          => $length,
            day             => 1,
            end_of_day_hour => $eod_hour,
            status          => 'active',
        );
        $season->save;
    }

    my ($char_model) = @{ $self->app->characters->find(
        sub { $_[0]->{account_id} eq $player_id && (!$season || $_[0]->{season_id} eq $season->getCol('id')) }
    ) };

    if (!$char_model) {
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
                my $pressure_state;
                if ($c) {
                    my $pct = ($c->{spent_so_far} // 0) / ($c->{soft_budget} || 1);
                    if        ($pct <= 0.50) { $pressure_state = 'mood_comfortable' }
                    elsif     ($pct <= 0.80) { $pressure_state = 'mood_interested' }
                    elsif     ($pct <= 1.00) { $pressure_state = 'mood_wary' }
                    elsif     ($pct <= 1.10) { $pressure_state = 'mood_strained' }
                    elsif     ($pct <  1.20) { $pressure_state = 'mood_leaving' }
                    else                     { $pressure_state = 'mood_over_absolute' }
                }
                $market_view = {
                    customer => {
                        faction_id      => $c->{faction_id},
                        faction_name    => $c->{faction_name},
                        disposition     => $c->{disposition} // 'unknown',
                        ($c->{pending_counter}
                            ? (pending_counter => $c->{pending_counter})
                            : ()),
                    },
                    irritation     => $c->{irritation} // 0,
                    pressure_state => $pressure_state,
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
                csrf_token   => $self->csrf_token,
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
                    label      => $season ? ($season->getCol('label') // 'Season') : undef,
                },
                world_message => $season ? $season->getCol('crier_message') : undef,
                factions      => $self->factions_data,
                faction_state => $season ? $season->getCol('faction_state') : undef,
                ($season_recap ? (season_recap => $season_recap) : ()),
                unit_status => $self->_unit_status,
            });
        },
        html => sub {
            $self->stash(
                authenticated     => 1,
                node_number       => $node_number,
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
                unit_status       => $self->_unit_status,
            );
            $self->render('game/show');
        },
    );
}

sub _unit_status ($self) {
    state $data = LoadFile($self->app->home . '/content/flavor/system_messages.yml');
    my $messages = $data->{unit_status} or return '';
    return $messages->[rand @$messages];
}

1;
