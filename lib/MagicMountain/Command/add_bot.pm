package MagicMountain::Command::add_bot;
use Mojo::Base 'Mojolicious::Command', '-signatures';

use YAML::XS qw(LoadFile);
use MagicMountain::BotName qw(random_bot_name);

has description => 'Add a bot NPC mid-season';
has usage => "Usage: $0 add-bot [--profile PROFILE_ID] [--name NAME] [--count N]\n"
          . "  --profile PROFILE_ID  Bot profile (default random)\n"
          . "  --name NAME           Character name (default random bot name)\n"
          . "  --count N             Number of bots to add (default 1)\n"
          . "  --list-profiles       List available bot profiles and exit\n";

sub run ($self, @args) {
    my ($profile_id, $name, $count, $list_profiles);
    while (@args) {
        my $arg = shift @args;
        if ($arg eq '--profile' && @args) {
            $profile_id = shift @args;
        } elsif ($arg eq '--name' && @args) {
            $name = shift @args;
        } elsif ($arg eq '--count' && @args) {
            $count = 0 + shift @args;
        } elsif ($arg eq '--list-profiles') {
            $list_profiles = 1;
        }
    }

    my $app  = $self->app;
    my $profiles_file = $app->home . '/content/bots.yml';
    my $profiles = -e $profiles_file ? LoadFile($profiles_file) : [];

    if ($list_profiles) {
        printf "%-30s %-20s\n", 'ID', 'Display Name';
        printf "%s\n", '-' x 50;
        for my $p (@$profiles) {
            printf "%-30s %-20s\n", $p->{id}, $p->{display_name} // '';
        }
        return;
    }

    my $season = $app->active_season
        or die "No active season found.\n";

    if ($profile_id) {
        my @match = grep { $_->{id} eq $profile_id } @$profiles;
        die "Unknown profile '$profile_id'. Valid: " . join(', ', map { $_->{id} } @$profiles) . "\n"
            unless @match;
    }

    my $bot_ap = $app->config->{default_action_points} // 20;
    my $accts  = $app->accounts;
    my $chars  = $app->characters;

    for my $i (1 .. $count) {
        my $pid = $profile_id // $profiles->[int(rand(@$profiles))]{id};
        my $bot_name = $name // random_bot_name();

        my $a = $accts->create(username => $bot_name);
        $a->save;

        $chars->create(
            name              => $bot_name,
            account_id        => $a->getCol('id'),
            season_id         => $season->getCol('id'),
            score             => 0,
            scrap             => 0,
            action_points     => $bot_ap,
            action_points_max => $bot_ap,
            is_bot            => 1,
            bot_profile_id    => $pid,
            onboarding        => 0,
            pending_notices   => 0,
        )->save;

        printf "Bot added: %s (%s)\n", $bot_name, $pid;
    }
}

1;
