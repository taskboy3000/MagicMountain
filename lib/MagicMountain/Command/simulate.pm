package MagicMountain::Command::simulate;
use Mojo::Base 'Mojolicious::Command', '-signatures';

use Getopt::Long qw(GetOptionsFromArray);
use File::Temp qw(tempdir);
use YAML::XS qw(LoadFile);
use MagicMountain::Model::Transcript;
use MagicMountain::Model::Season;
use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::Session;
use MagicMountain::Model::ShedItem;
use MagicMountain::Model::Transcript;

has description => 'Run a bot simulation season with configurable policies.';
has usage => "usage: $0 simulate [OPTIONS]\n"
           . "  --count N         Number of bots (default 5)\n"
           . "  --days N          Season length in days (default 30)\n"
           . "  --seed N          RNG seed\n"
           . "  --output FILE     Transcript output path\n"
           . "  --skill-profile S Skill levels, e.g. 'prospecting=2,upcycling=1'\n"
           . "  --profile FILE    Bot profile YAML (default content/bots.yml)\n"
           . "  --profile-weights W  Weighted profile distribution, e.g. 'a=3,b=1'\n"
           . "  --counter-offers  Enable counter-offer haggle step\n"
           . "  --multi-item      Enable multi-item sales per market visit\n";

sub run ($self, @args) {
    my $count   = 5;
    my $days    = 30;
    my $seed    = undef;
    my $output  = undef;
    my $skill_profile = undef;
    my $profile_file  = undef;
    my $weights_str   = undef;
    my $counter_offers = 0;
    my $multi_item     = 0;

    GetOptionsFromArray(\@args,
        'count=i'           => \$count,
        'days=i'            => \$days,
        'seed=i'            => \$seed,
        'output=s'          => \$output,
        'skill-profile=s'   => \$skill_profile,
        'profile=s'         => \$profile_file,
        'profile-weights=s' => \$weights_str,
        'counter-offers!'   => \$counter_offers,
        'multi-item!'       => \$multi_item,
    );

    srand($seed) if defined $seed;

    my $app = $self->app;
    my $data_dir = tempdir(CLEANUP => 1);
    local $ENV{MM_DATA_DIR} = $data_dir;
    delete $app->{dataDir};
    local $ENV{MM_SKIP_SEASON_CHECK} = 1;

    delete $app->{$_} for qw(accounts characters seasons shed session_store transcript prospecting market audit_log faction_snapshots);

    MagicMountain::Model::Account->new(file => "$data_dir/accounts.json")->save;
    MagicMountain::Model::Character->new(file => "$data_dir/characters.json")->save;
    MagicMountain::Model::Session->new(file => "$data_dir/sessions.json")->save;
    MagicMountain::Model->new(file => "$data_dir/activities.json")->save;
    MagicMountain::Model::ShedItem->new(file => "$data_dir/shed.json")->save;
    MagicMountain::Model::Season->new(file => "$data_dir/seasons.json")->save;

    $app->config->{market_counter_offers} = $counter_offers;
    $app->config->{market_multi_item}     = $multi_item;

    my $accts  = $app->accounts;
    my $chars  = $app->characters;
    my $season = $app->seasons;
    my $shed   = $app->shed;

    my $s = $season->create(
        label   => 'Simulation 1',
        length  => $days,
        day     => 1,
        status  => 'active',
    );
    $s->save;

    # Load profiles
    $profile_file //= $app->home . '/content/bots.yml';
    my $profiles = (-e $profile_file) ? LoadFile($profile_file) : [];
    my @profiles = @$profiles;

    # Fallback to a single default profile if none defined
    if (!@profiles) {
        @profiles = ({
            id => 'default',
            push_policy => { name => 'stage_guard', params => { stop_at => 'unstable' } },
            sell_policy => { name => 'opportunist' },
            skill_profile => { prospecting => 0, upcycling => 0, selling => 0 },
        });
    }

    # Parse profile weights
    my @profile_pool;
    if ($weights_str) {
        my %weights;
        for my $part (split /,/, $weights_str) {
            $part =~ s/\s+//g;
            my ($key, $weight) = split /=/, $part;
            $weights{$key} = int($weight // 1);
        }
        for my $p (@profiles) {
            next unless exists $weights{$p->{id}};
            push @profile_pool, $p for 1 .. $weights{$p->{id}};
        }
    }

    # Parse skill profile (used only when no profile YAML loaded)
    my %skill_defaults = (prospecting => 0, upcycling => 0, selling => 0);
    if ($skill_profile && @profiles == 1 && $profiles[0]->{id} eq 'default') {
        for my $part (split /,/, $skill_profile) {
            $part =~ s/\s+//g;
            my ($key, $val) = split /=/, $part;
            $skill_defaults{$key} = int($val // 0) if exists $skill_defaults{$key};
        }
    }

    # Create bot accounts, characters, and assign profiles
    my @bot_chars;
    my %char_profile;
    for my $i (1 .. $count) {
        my $name = sprintf("bot-%03d", $i);
        my $profile;
        if (@profile_pool) {
            $profile = $profile_pool[ int(rand(scalar @profile_pool)) ];
        } else {
            $profile = $profiles[ ($i - 1) % @profiles ];
        }

        my $sk = $profile->{skill_profile} // \%skill_defaults;

        my $a = $accts->create(username => $name);
        $a->save;

        my $c = $chars->create(
            name              => $name,
            account_id        => $a->getCol('id'),
            season_id         => $s->getCol('id'),
            score             => 0,
            scrap             => 0,
            action_points     => 15,
            action_points_max => 15,
            skill_prospecting => $sk->{prospecting} // 0,
            skill_upcycling   => $sk->{upcycling} // 0,
            skill_selling     => $sk->{selling} // 0,
        );
        $c->save;
        push @bot_chars, $c;
        $char_profile{$c->getCol('id')} = $profile;
    }

    # Open transcript
    my $transcript_file = "$data_dir/transcript.jsonl";
    $app->{transcript} = MagicMountain::Model::Transcript->new(file => $transcript_file);
    my $transcript = $app->transcript;

    # Build bot roster for sim_start
    my @bot_roster;
    for my $c (@bot_chars) {
        my $p = $char_profile{$c->getCol('id')};
        push @bot_roster, {
            name         => $c->getCol('name'),
            char_id      => $c->getCol('id'),
            profile_id   => $p->{id},
            push_policy  => $p->{push_policy}{name},
            push_params  => $p->{push_policy}{params},
            sell_policy  => $p->{sell_policy}{name},
            sell_params  => $p->{sell_policy}{params},
            skills       => $p->{skill_profile},
        };
    }

    $transcript->log_event({
        type      => 'sim_start',
        run_id    => $s->getCol('id'),
        bot_count => $count,
        days      => $days,
        bots      => \@bot_roster,
        narrative => sprintf("Simulation %s: %d bots, %d days, %d profiles.",
            $s->getCol('id'), $count, $days, scalar @profiles),
    });

    $app->shed_manager->log_transcript(1);
    $app->bot_runner->transcript($transcript);

    # Run simulation
    my $maint = $app->maintenance;
    my @chars = @bot_chars;
    for my $day (1 .. $days) {
        $app->seasons->load;
        for my $char (@chars) {
            my $profile = $char_profile{$char->getCol('id')};
            next unless $profile;
            my $result = $app->bot_runner->run_day($char, $profile);
            $app->log->warn(sprintf("Bot %s run failed: %s",
                $char->getCol('name') // '?',
                $result->{error} // 'unknown'))
                unless $result->{ok};
        }
        $maint->on_maintenance->($maint) if $day < $days;
        @chars = @{ $app->characters->find(sub { $_[0]->{season_id} eq $s->getCol('id') }) };
    }

    # Finalize the season (triggers clearance sale, creates SeasonRecords)
    my $finalize_result = eval { MagicMountain::Model::Season->finalize($app) };
    if ($@) {
        $app->log->warn("Season finalization failed: $@");
    } else {
        $app->log->info(sprintf("Season finalized: %d characters.", $finalize_result->{character_count} // 0));
    }

    $transcript->log_event({
        type      => 'sim_end',
        run_id    => $s->getCol('id'),
        bots      => \@bot_roster,
        narrative => sprintf("Simulation %s complete.", $s->getCol('id')),
    });

    if ($output) {
        $transcript->export_to($output);
        $app->log->info(sprintf("Transcript written to %s", $output));
    } else {
        print "Transcript: $transcript_file\n";
    }
}

1;
