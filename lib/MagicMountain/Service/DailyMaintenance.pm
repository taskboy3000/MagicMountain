package MagicMountain::Service::DailyMaintenance;
use Mojo::Base '-base', '-signatures';

use Mojo::UserAgent;
use Mojo::IOLoop;

use MagicMountain::Bot::Agent;
use MagicMountain::Bot::Routine;
use MagicMountain::Service::SeasonFinalizer;

has app => sub { die "app is required" };

sub run_day ($self, $maint) {
    my $season = $self->app->active_season;
    return unless $season;

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

    my $fs = $season->getCol('faction_state') // {};
    for my $fid (keys %$fs) {
        $fs->{$fid}->{daily_intake} = 0;
        $fs->{$fid}->{days_since_purchase}++;
    }
    $season->setCol('faction_state', $fs);

    $self->app->dominance_service->calculate_climate($season);

    if ($self->app->can('random_events')) {
        my $global_event = $self->app->random_events->draw(
            pool    => 'global',
            trigger => 'day_start',
            context => {
                season        => $season,
                faction_state => $fs,
            },
        );
        if ($global_event) {
            $self->app->random_events->apply_effects(
                $global_event, 'global',
                { season => $season, faction_state => $fs },
            );
            $season->setCol('global_event_text', $global_event->{text});
            $self->app->log->info(
                sprintf("Global event [%s]: %s", $global_event->{id}, $global_event->{text})
            );
        }
    }

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

sub catch_up_missed_cycles ($self) {
    my $app = $self->app;
    $app->seasons->load;
    my $active = $app->seasons->find(sub { ($_[0]->{status} // '') eq 'active' });
    return unless @$active;

    my $season = $active->[0];
    my $day    = $season->getCol('day') // 0;
    my $length = $season->getCol('length') // 30;
    if ($day > $length) {
        $app->log->info(sprintf(
            "Auto-finalizing season '%s' at day %d (length %d)",
            $season->getCol('label') // '?', $day, $length
        ));
        MagicMountain::Service::SeasonFinalizer->new(app => $app)->finalize;
        return;
    }

    my $last = $season->getCol('last_maintenance');
    return unless defined $last;

    my $maint = $app->maintenance;
    my $boundary = $maint->recent_maintenance_boundary;

    if ($last < $boundary) {
        my $missed = int(($boundary - $last) / 86400);
        $app->log->info("Catch-up: $missed missed maintenance cycle(s)");
        $maint->catch_up($missed);
    }
}

sub open_bot_window ($self, $maint) {
    my $app = $self->app;

    my $bots_cfg = $app->config->{bots} // {};
    return 0 unless ($bots_cfg->{count} // 0) > 0;

    $app->characters->load;
    my $bot_chars = $app->characters->find(sub {
        $_[0]->{season_id} eq $app->active_season->getCol('id')
        && $_[0]->{is_bot}
    });
    return 0 unless @$bot_chars;

    $maint->bot_window_open(1);

    my $daemon_url = $ENV{MOUNTAIN_DAEMON_URL} // $app->config->{port} // 9000;
    $daemon_url = "http://localhost:$daemon_url" if $daemon_url =~ /^\d+$/;
    $daemon_url =~ s|/$||;

    my $deadline_minutes = $app->config->{maintenance_bot_deadline_minutes};
    $deadline_minutes = 10 unless defined $deadline_minutes;

    $app->log->info("Opening bot window (deadline: ${deadline_minutes}m)");

    my $deadline_timer;
    my $deadline_fired = 0;
    my $subprocess;

    $subprocess = Mojo::IOLoop->subprocess(
        sub {
            my $grandchild;
            $SIG{TERM} = sub {
                kill('TERM', $grandchild) if $grandchild && kill(0, $grandchild);
                exit(1);
            };

            local $ENV{MM_SKIP_CATCHUP} = '1';
            local $ENV{MOUNTAIN_DAEMON_URL} = $daemon_url;
            my @cmd = ($^X, '-Ilib', 'script/mountain', 'bot-turn');
            system(@cmd);
            return $? >> 8;
        },
        sub ($subprocess, $err, @results) {
            my $exit_code = $results[0] // -1;
            Mojo::IOLoop->cancel($deadline_timer) if $deadline_timer;
            $app->log->info("Bot window finished with code $exit_code");
            $maint->_rollover;
        },
    );

    if ($deadline_minutes > 0) {
        $deadline_timer = Mojo::IOLoop->timer($deadline_minutes * 60 => sub {
            return if $deadline_fired++;
            $app->log->warn("Bot window deadline reached — cancelling bot work");
            my $pid;
            if ($subprocess) {
                $pid = $subprocess->pid;
            }
            kill('TERM', $pid) if $pid;
        });
    }

    return 1;
}

1;
