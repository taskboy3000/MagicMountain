package MagicMountain::Service::DailyMaintenance;
use Mojo::Base '-base', '-signatures';

use List::Util 'shuffle';
use Mojo::UserAgent;

use MagicMountain::Bot::Agent;
use MagicMountain::Bot::Routine;
use MagicMountain::Service::SeasonFinalizer;

has app => sub { die "app is required" };

sub run_day ($self, $maint) {
    my $season = $self->app->active_season;
    return unless $season;

    $self->_run_bots($maint, $season) unless $maint->_catching_up;

    # Clear yesterday's modifiers before drawing new ones
    $season->setCol('daily_modifiers', {});
    $season->setCol('global_event_text', undef);

    my $day    = $season->getCol('day') + 1;
    $self->app->log->info(sprintf("Maintenance: %s day %d -> %d",
        $season->getCol('label') // '?', $day - 1, $day));
    $season->setCol('day', $day);
    $season->save;

    $self->app->characters->load;
    my $chars = $self->app->characters->find(sub { $_[0]->{season_id} eq $season->getCol('id') });
    for my $char (@$chars) {
        my $max = $char->getCol('action_points_max') // $self->app->config->{default_action_points} // 15;
        $char->setCol('action_points', $max);
        $char->setCol('smuggle_reroll_used', 0);
        $char->save;
    }

    $self->app->shed_manager->apply_decay;

    # Market dynamics reset (daily_intake=0, days_since_purchase++)
    my $fs = $season->getCol('faction_state') // {};
    for my $fid (keys %$fs) {
        $fs->{$fid}->{daily_intake} = 0;
        $fs->{$fid}->{days_since_purchase}++;
    }
    $season->setCol('faction_state', $fs);

    # Faction climate calculation
    $self->app->dominance_service->calculate_climate($season);

    # Global event: draw and apply modifiers
    if ($self->app->can('random_events')) {
        my $global_event = $self->app->random_events->draw(
            pool    => 'global',
            trigger => 'day_start',
            context => {
                season        => $season,
                faction_state => \%$fs,
            },
        );
        if ($global_event) {
            $self->app->random_events->apply_effects(
                $global_event, 'global',
                { season => $season, faction_state => \%$fs },
            );
            $season->setCol('global_event_text', $global_event->{text});
            $self->app->log->info(
                sprintf("Global event [%s]: %s", $global_event->{id}, $global_event->{text})
            );
        }
    }

    # Crier generation (reads global_event_text first)
    my $crier_opts = $maint->_catching_up ? { time_warp => 1 } : {};
    my $msg = $self->app->crier->generate($season, $crier_opts);
    $season->setCol('crier_message', $msg);
    $season->setCol('crier_snapshot', $season->getCol('faction_state'));

    for my $fid (keys %$fs) {
        $self->app->faction_snapshots->create(
            season_id          => $season->getCol('id'),
            day                => $day,
            faction_id         => $fid,
            influence          => $fs->{$fid}{influence} // 0,
            artifacts_received => $fs->{$fid}{artifacts_received} // 0,
            intake_by_trait    => $fs->{$fid}{intake_by_trait} // {},
        )->save;
    }

    $season->setCol('faction_state', $fs);

    $self->app->log_event({
        type      => 'faction_snapshot',
        day       => $day,
        factions  => $season->getCol('faction_state') // {},
        narrative => sprintf("Day %d faction snapshot: %s",
            $day, $msg // 'no message'),
    }, 'season');

    $season->setCol('last_maintenance', CORE::time);
    $season->save;

    my $length = $season->getCol('length');
    if ($day > $length) {
        $self->app->log->info(sprintf(
            "Season '%s' day %d exceeds configured length %d — finalizing",
            $season->getCol('label'), $day, $length
        ));
        MagicMountain::Service::SeasonFinalizer->new(app => $self->app)->finalize;
    }
}

sub _run_bots ($self, $maint, $season) {
    my $bots_cfg = $self->app->config->{bots} // {};
    return unless ($bots_cfg->{count} // 0) > 0;

    my $bot_chars = $self->app->characters->find(sub {
        $_[0]->{season_id} eq $season->getCol('id')
        && $_[0]->{is_bot}
    });
    return unless @$bot_chars;

    my $seed = $season->getCol('day') // 0;
    my $id_str = $season->getCol('id') // '';
    for my $c (unpack('C*', $id_str)) {
        $seed = (($seed << 5) ^ $seed ^ $c) & 0x7FFFFFFF;
    }
    srand($seed);
    my @shuffled = shuffle(@$bot_chars);

    my $port = $self->app->config->{port} // 9000;
    my $svc_token = $self->app->config->{bot_service_token};
    my $base_url = "http://localhost:$port";

    for my $bot_char (@shuffled) {
        eval {
            my $ua = Mojo::UserAgent->new;
            my $agent = MagicMountain::Bot::Agent->new(
                ua        => $ua,
                base_url  => $base_url,
                svc_token => $svc_token,
            );
            $agent->login($bot_char->getCol('name'));
            my $routine = MagicMountain::Bot::Routine->new(
                agent      => $agent,
                profile_id => $bot_char->getCol('bot_profile_id'),
            );
            $routine->run_day;
        };
        if ($@) {
            $self->app->log->warn(sprintf(
                "Bot %s daily run failed: %s",
                $bot_char->getCol('name') // '?', $@
            ));
        }
    }
}

1;
