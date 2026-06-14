package MagicMountain;

use File::Basename;
use File::Find;
use Mojo::Base 'Mojolicious', -signatures;
use Mojo::Home;
use Mojo::IOLoop;
use Time::HiRes;

use MagicMountain::Model::Account;
use MagicMountain::Model::AuditLog;
use MagicMountain::Model::Character;
use MagicMountain::Model::Season;
use MagicMountain::Model::Session;
use MagicMountain::Maintenance;
use MagicMountain::Activity::Prospecting;

has configFile => sub ($self) {
    $ENV{MM_CFG_FILE} || $self->home . '/' . $self->moniker . '.yml';
};

has defaultConfig => sub ($self) {
    return {
        secrets                   => [ 'override-me' ],
        session_timeout_minutes   => 60,
        end_of_day_hour           => 0,
        maintenance_window_minutes => 5,
    }
};

has dataDir => sub ($self) {
    $ENV{MM_DATA_DIR} || $self->home . '/data';
};

has accounts => sub ($self) {
    MagicMountain::Model::Account->new(
        file => $self->dataDir . '/accounts.json',
        log => $self->app->log
    );
};

has session_store => sub ($self) {
    MagicMountain::Model::Session->new(
        file => $self->dataDir . '/sessions.json',
        log => $self->app->log
    );
};

has seasons => sub ($self) {
    MagicMountain::Model::Season->new(
        file => $self->dataDir . '/seasons.json',
        log => $self->app->log
    );
};

has characters => sub ($self) {
    MagicMountain::Model::Character->new(
        file => $self->dataDir . '/characters.json',
        log  => $self->app->log
    );
};

has prospecting => sub ($self) {
    my $p = MagicMountain::Activity::Prospecting->new(
        file             => $self->dataDir . '/activities.json',
        app              => $self,
        content_filename => $self->home . '/content/prospecting.yml',
        log              => $self->log,
    );
    $p->load_content;
    return $p;
};

has maintenance => sub ($self) {
    my $maint = MagicMountain::Maintenance->new(
        app            => $self,
        end_of_day_hour => $self->config->{end_of_day_hour} // 0,
    );
    $maint->next_run;
    return $maint;
};

has audit_log => sub ($self) {
    MagicMountain::Model::AuditLog->new(
        file => $self->dataDir . '/audit.jsonl',
    );
};

sub startup ($self) {
    $self->log->debug(sprintf("[%s] startup: mode=%s",
                        $self->moniker, $self->mode
                    )
    );
    $self->log->debug("Attempting to load config from: " . $self->configFile);
    $self->plugin('NotYAMLConfig' => {
            file => $self->configFile,
            default => $self->defaultConfig
        }
    );

    push @{ $self->commands->namespaces }, 'MagicMountain::Command';
    $self->app->log->debug("Secrets: " . join(", ", @{ $self->config->{secrets} }));
    $self->secrets([ $self->config->{secrets} ] );
    $self->sessions->cookie_name('mm_session');
    $self->sessions->default_expiration(86400);

    if (!-e $self->dataDir) {
        mkdir $self->dataDir or die("Cannot make dataDir[$!]: " . $self->dataDir);
    }

    $self->renderer->cache->max_keys(0);
    $self->defaults(layout => 'default');

    $self->helper(is_maintenance => sub ($c) {
        return $c->app->maintenance->in_maintenance;
    });

    $self->helper(current_player => sub ($c) {
        my $player_id = $c->session('playerId');
        return undef unless $player_id;
        my $session = $c->app->session_store->find_by_player_id($player_id);
        return undef unless $session;
        my $timeout = $c->app->config->{session_timeout_minutes} // 60;
        if ($session->is_expired($timeout)) {
            $c->app->session_store->delete($session->getCol('id'));
            $c->session(expires => 1);
            return undef;
        }
        $session->touch;
        return $player_id;
    });

    Mojo::IOLoop->recurring(60 => sub {
        $self->maintenance->dailyMaintenance;
    });

    $self->buildRoutes;
}

sub buildRoutes ($self) {
    my $r = $self->routes;

    # Public read-only routes (accessible during maintenance)
    $r->get('/')->to('root#index')->name('root');
    $r->get('/login')->to('sessions#login_form')->name('login_form');
    $r->get('/logout')->to('sessions#logout')->name('logout');
    $r->delete('/sessions')->to('sessions#destroy')->name('logout_api');

    # Routes blocked during maintenance
    my $no_maintenance = $r->under('/' => sub ($c) {
        if ($c->is_maintenance) {
            $c->render(text => 'Maintenance in progress', status => 503);
            return undef;
        }
        return 1;
    });
    $no_maintenance->post('/sessions')->to('sessions#create')->name('login');

    # Authenticated routes (also blocked during maintenance)
    my $auth = $no_maintenance->under('/' => sub ($c) {
        my $player_id = $c->current_player;
        unless ($player_id) {
            $c->redirect_to('login_form');
            return undef;
        }
        return 1;
    });
    $auth->get('/player')->to('player#show')->name('player');
    $auth->delete('/player')->to('player#destroy')->name('delete_player');
    $auth->get('/game')->to('game#show')->name('game');

    # Future (under auth):
    $auth->post('/artifact/begin')->to('artifact#begin');
    $auth->post('/artifact/push')->to('artifact#push');
    $auth->post('/artifact/stop')->to('artifact#stop');
    $auth->post('/sale/:faction_id')->to('sale#create');
    # $auth->get('/leaderboard')->to('leaderboard#index');
}


1;