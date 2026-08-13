package MagicMountain::Command::bot_turn;
use Mojo::Base 'Mojolicious::Command', '-signatures';

use Getopt::Long qw(GetOptionsFromArray);
use List::Util 'shuffle';
use Mojo::UserAgent;

use MagicMountain::Bot::Agent;
use MagicMountain::Bot::Routine;

has description => 'Run bot turns for the active season (or a single bot)';
has usage       => "Usage: $0 bot-turn [bot-id]\n";

sub run ($self, @args) {
    my $app = $self->app;

    my $single_bot_id;
    GetOptionsFromArray(\@args,
        'bot-id=s' => \$single_bot_id,
    );

    my $season = $app->active_season;
    if (!$season) {
        $self->app->log->info('No active season — nothing to do');
        return 0;
    }

    my $bots_cfg = $app->config->{bots} // {};
    if (($bots_cfg->{count} // 0) <= 0) {
        $self->app->log->info('Bot count is 0 — nothing to do');
        return 0;
    }

    my $base_url = $ENV{MOUNTAIN_DAEMON_URL}
        // $app->config->{port}
        // 'http://localhost:9000';
    $base_url = "http://localhost:$base_url" if $base_url =~ /^\d+$/;
    $base_url =~ s|/$||;

    my $svc_token = $app->config->{bot_service_token};

    my $season_id = $season->getCol('id') // '';
    my $day       = $season->getCol('day') // 0;
    my $seed = $day;
    for my $c (unpack('C*', $season_id)) {
        $seed = (($seed << 5) ^ $seed ^ $c) & 0x7FFFFFFF;
    }
    srand($seed);

    $app->characters->load;
    my @bot_chars = @{ $app->characters->find(sub {
        $_[0]->{season_id} eq $season->getCol('id')
        && $_[0]->{is_bot}
    }) };

    if (!@bot_chars) {
        $self->app->log->info('No bot characters in active season — nothing to do');
        return 0;
    }

    if ($single_bot_id) {
        my ($match) = grep { $_->getCol('id') eq $single_bot_id } @bot_chars;
        if (!$match) {
            $self->app->log->warn("Bot '$single_bot_id' not found");
            return 1;
        }
        @bot_chars = ($match);
    } else {
        @bot_chars = shuffle(@bot_chars);
    }

    my $failed = 0;
    for my $bot_char (@bot_chars) {
        my $name = $bot_char->getCol('name') // '?';
        eval {
            my $ua = Mojo::UserAgent->new;
            my $agent = MagicMountain::Bot::Agent->new(
                ua        => $ua,
                base_url  => $base_url,
                svc_token => $svc_token,
            );
            $agent->login($name);
            my $routine = MagicMountain::Bot::Routine->new(
                agent      => $agent,
                profile_id => $bot_char->getCol('bot_profile_id'),
            );
            $routine->run_day;
        };
        if ($@) {
            $self->app->log->warn(sprintf(
                "Bot %s daily run failed: %s", $name, $@
            ));
            $failed = 1;
        }
    }

    return $failed ? 1 : 0;
}

1;
