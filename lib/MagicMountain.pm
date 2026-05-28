package MagicMountain;

use File::Basename;
use File::Find;
use Mojo::Base 'Mojolicious', -signatures;
use Mojo::Home;
use Time::HiRes;

use MagicMountain::Model::Account;

has configFile => sub ($self) {
    $ENV{MM_CFG_FILE} || $self->home . '/' . $self->moniker . '.yml';
};

has defaultConfig => sub ($self) {
    return {
        secrets => [ 'override-me' ],
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

    #push @{ $self->commands->namespaces }, 'MagicMountain::Command';
    $self->app->log->debug("Secrets: " . join(", ", @{ $self->config->{secrets} }));
    $self->secrets([ $self->config->{secrets} ] );
    $self->sessions->cookie_name('mm_session');
    $self->sessions->default_expiration(86400);

    if (!-e $self->dataDir) {
        mkdir $self->dataDir or die("Cannot make dataDir[$!]: " . $self->dataDir);
    }

    $self->renderer->cache->max_keys(0);
    $self->defaults(layout => 'layouts/default.ep');
    $self->buildRoutes;
}

sub buildRoutes ($self) {
    my $r = $self->routes;

    $r->get('/')->to('sessions#loginForm')->name('login_form');
    $r->post('/api/sessions')->to('sessions#create')->name('login');
    $r->delete('/api/sessions')->to('sessions#destroy')->name('logout');

    # TODO: name this controller
    # $r->post('/api/action')->to('play#action');
    # $r->get('/api/leaderboard')->to('play#leaderboard');
    # $r->post('/api/admin/advance-day')->to('admin#advanceDay');
}


1;