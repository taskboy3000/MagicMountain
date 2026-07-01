package MagicMountain::Controller::Game;
use Mojo::Base 'MagicMountain::Controller', '-signatures';
use Mojo::JSON qw(encode_json);
use YAML::XS qw(LoadFile);

use MagicMountain::Service::SeasonManager;

sub show ($self) {
    my $player_id = $self->current_player;

    if (!$player_id) {
        $self->respond_to(
            json => sub { $self->render(json => { ok => 0, error => 'Not logged in' }, status => 401) },
            html => sub {
                $self->stash(authenticated => 0, player_name => '—', node_number => '—', unit_status => '',
                    admin_email => $self->app->config->{admin_email} // '');
                $self->render('game/show');
            },
        );
        return;
    }

    my $account = $self->app->accounts->get($player_id);
    $self->app->session_store->load;
    my $sess = $self->app->session_store->find_by_player_id($player_id);
    my $node_number = $sess ? $sess->getCol('node_number') // '07' : '07';

    my $season_mgr = MagicMountain::Service::SeasonManager->new(app => $self->app);
    my ($season, $season_recap) = $season_mgr->ensure_season($player_id);
    my ($char_model, $onboarding_notices) = $season_mgr->ensure_character($account, $season);

    my $row = $char_model->row;
    my $prospecting_view = $char_model->prospecting_view;
    my $market_view      = $char_model->market_view;
    my $skills           = $char_model->player_skills;
    my $shed_items       = $char_model->shed_items;

    my $activity;
    my $id = $row->{pending_activity_id};
    if ($id) {
        $self->app->prospecting->load;
        my $type = $self->app->prospecting->table->{$id}{type} // '';
        if ($type eq 'prospecting') {
            $activity = $self->app->prospecting->get($id);
        } elsif ($type eq 'market_visit') {
            $activity = $self->app->market->get($id);
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
                ($char_model->getCol('seen_orientation') || $char_model->getCol('is_bot') ? () : (show_orientation => 1)),
                onboarding_notices => $onboarding_notices,
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
                admin_email       => $self->app->config->{admin_email} // '',
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
