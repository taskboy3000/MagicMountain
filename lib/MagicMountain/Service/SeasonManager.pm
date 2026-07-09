package MagicMountain::Service::SeasonManager;
use Mojo::Base '-base', '-signatures';
use YAML::XS qw(LoadFile);
use List::Util 'sum';
use MagicMountain::BotName qw(random_bot_name);

has app => sub { die "app is required" };

sub ensure_season ($self, $player_id) {
    my $season = $self->app->active_season;
    my $season_recap;

    $self->app->season_records->load;
    my $archived = $self->app->seasons->find(sub { ($_[0]->{status} // '') eq 'archived' });
    if (@$archived) {
        my @sorted = sort { ($b->getCol('day') // 0) <=> ($a->getCol('day') // 0) } @$archived;
        my $last = $sorted[0];
        my $recs = $self->app->season_records->find(sub { $_[0]->{player_id} eq $player_id && $_[0]->{season_id} eq $last->getCol('id') });
        if (@$recs) {
            my $season_id = $season ? $season->getCol('id') : undef;
            my $existing = $self->app->characters->find(sub { $_[0]->{account_id} eq $player_id && (!$season_id || $_[0]->{season_id} eq $season_id) });
            if (!@$existing) {
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
    }

    if (!$season) {
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

        $self->seed_bots($season);
    }

    return ($season, $season_recap);
}

sub ensure_character ($self, $account, $season) {
    my $player_id = $account->getCol('id');
    my $season_id = $season ? $season->getCol('id') : undef;

    my ($char_model) = @{ $self->app->characters->find(
        sub { $_[0]->{account_id} eq $player_id && (!$season_id || $_[0]->{season_id} eq $season_id) }
    ) };

    if (!$char_model) {
        my $daily_ap = $self->app->config->{default_action_points} // 15;
        $char_model = $self->app->characters->create(
            name                  => $account->getCol('username'),
            account_id            => $player_id,
            season_id             => $season_id,
            score                 => 0,
            scrap                 => 0,
            action_points         => $season ? $daily_ap : 0,
            action_points_max     => $daily_ap,
            pending_activity_id   => undef,
        );
        $char_model->save;
    }

    my $notices = $self->_update_onboarding($char_model);
    return ($char_model, $notices);
}

use constant {
    BIT_BAZAAR   => 1,
    BIT_FACTIONS => 2,
    BIT_SKILLS   => 4,
    BIT_INTEL    => 8,
};

sub _update_onboarding ($self, $char) {
    my $current = $char->getCol('onboarding') // 0;

    my $scrap = $char->getCol('scrap') // 0;
    my $faction_sales = $char->getCol('faction_sales') // {};
    my $total_sales = sum(values %$faction_sales) // 0;

    my $shed_count = scalar @{ $self->app->shed->find(
        sub { $_[0]->{char_id} eq $char->getCol('id') }
    ) };

    my $skill_unlock = $self->app->config->{onboarding_skill_unlock_scrap} // 100;

    my $should = 0;
    $should |= BIT_BAZAAR   if $shed_count >= 1;
    $should |= BIT_FACTIONS if $total_sales >= 3;
    $should |= BIT_SKILLS   if $scrap >= $skill_unlock;
    $should |= BIT_INTEL    if ($should & BIT_SKILLS);

    my $new = $should & ~$current;
    return [] unless $new;

    my $pending = ($char->getCol('pending_notices') // 0) | $new;
    $char->setCol('onboarding', $current | $new);
    $char->setCol('pending_notices', $pending);
    $char->save;

    my %ID_FOR_BIT = (1 => 'bazaar', 2 => 'factions', 4 => 'skills', 8 => 'pvp');

    my @notices;
    for my $bit (BIT_BAZAAR, BIT_FACTIONS, BIT_SKILLS, BIT_INTEL) {
        push @notices, $ID_FOR_BIT{$bit} if $new & $bit;
    }
    return \@notices;
}

sub rank_of ($self, $char) {
    my $season = $self->app->active_season or return;
    $self->app->characters->load;
    my $chars = $self->app->characters->find(
        sub { $_[0]->{season_id} eq $season->getCol('id') }
    );
    my @sorted = sort { ($b->getCol('score') // 0) <=> ($a->getCol('score') // 0) } @$chars;
    for my $i (0 .. $#sorted) {
        return $i + 1 if $sorted[$i]->getCol('id') eq $char->getCol('id');
    }
    return;
}

sub seed_bots ($self, $season) {
    my $bots_cfg = $self->app->config->{bots} // {};
    my $count    = $bots_cfg->{count} // 0;
    return unless $count > 0;

    my $profile_list = $bots_cfg->{profiles} // [];
    return unless @$profile_list;

    my $file = $self->app->home . '/content/bots.yml';
    return unless -e $file;
    my $profiles = LoadFile($file);
    my %by_id = map { $_->{id} => $_ } @$profiles;

    my $bot_ap = $bots_cfg->{action_points} // $self->app->config->{default_action_points} // 15;
    my $season_id = $season->getCol('id');
    my $accts = $self->app->accounts;
    my $chars = $self->app->characters;

    for my $i (1 .. $count) {
        my $profile_id = $profile_list->[($i - 1) % @$profile_list]{id};
        my $profile    = $by_id{$profile_id} or next;

        my $name = random_bot_name();
        my $a = $accts->create(username => $name);
        $a->save;

        $chars->create(
            name              => $name,
            account_id        => $a->getCol('id'),
            season_id         => $season_id,
            score             => 0,
            scrap             => 0,
            action_points     => $bot_ap,
            action_points_max => $bot_ap,
            is_bot            => 1,
            bot_profile_id    => $profile_id,
            onboarding        => 0,
            pending_notices   => 0,
        )->save;
    }
}

1;
