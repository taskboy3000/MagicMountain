package MagicMountain::Command::simulate;
use Mojo::Base 'Mojolicious::Command', '-signatures';

use Getopt::Long qw(GetOptionsFromArray);
use File::Temp qw(tempdir);
use File::Slurp qw(write_file);
use YAML::XS qw(LoadFile);
use MagicMountain::Model::Transcript;
use MagicMountain::Model::Season;
use MagicMountain::Model::Account;
use MagicMountain::Model::Character;
use MagicMountain::Model::Session;
use MagicMountain::Model::ShedItem;
use MagicMountain::Bot::PushPolicy;
use MagicMountain::Bot::SellPolicy;

my %PRESSURE_RANK = (
    mood_comfortable   => 0,
    mood_interested    => 1,
    mood_wary          => 2,
    mood_strained      => 3,
    mood_leaving       => 4,
    mood_over_absolute => 5,
);

sub _pressure_at_or_beyond {
    my ($state, $threshold) = @_;
    return 0 unless $state && $threshold;
    return ($PRESSURE_RANK{$state} // 0) >= ($PRESSURE_RANK{$threshold} // 0);
}

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

    # Run simulation
    my $maint = $app->maintenance;
    my @chars = @bot_chars;
    for my $day (1 .. $days) {
        $app->seasons->load;
        for my $char (@chars) {
            my $profile = $char_profile{$char->getCol('id')};
            $self->_run_bot_day($app, $char, $profile, $transcript) if $profile;
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

sub _run_bot_day ($self, $app, $char, $profile, $transcript) {
    my $prospecting = $app->prospecting;
    my $market      = $app->market;
    my $shed        = $app->shed;
    my $profile_id  = $profile->{id};
    my $push_pol    = $profile->{push_policy};
    my $sell_pol    = $profile->{sell_policy};
    my $char_name   = $char->getCol('name');

    # Prospecting phase
    while (($char->getCol('action_points') // 0) >= 2) {
        my $activity = $prospecting->create(char_id => $char->getCol('id'));
        my $result = $activity->dispatch($char, 'begin');
        last unless $result->{view}{ok};

        while (1) {
            my $r = $activity->dispatch($char, 'push');
            my $view = $r->{view};
            last unless $view->{ok};

            if ($view->{result} eq 'collapse' || $view->{result} eq 'breakthrough') {
                last;
            }

            if ($view->{result} eq 'push') {
                my $art = $activity->artifact;
                my $should_stop = MagicMountain::Bot::PushPolicy::evaluate($char, $art, $push_pol);
                if ($should_stop) {
                    $activity->dispatch($char, 'stop');
                    $transcript->log_event({
                        type       => 'policy_push_stop',
                        player     => $char_name,
                        profile_id => $profile_id,
                        policy     => $push_pol->{name},
                        params     => $push_pol->{params},
                        stage      => $art->{stage},
                        value      => $art->{value},
                        push_count => $art->{push_count},
                        narrative  => sprintf("%s stopped pushing via %s (stage=%s, value=%d, pushes=%d).",
                            $char_name, $push_pol->{name},
                            $art->{stage} // '?',
                            $art->{value} // 0,
                            $art->{push_count} // 0),
                    });
                    last;
                }
            }
        }
    }

    # Market phase
    while (($char->getCol('action_points') // 0) >= 1) {
        my $shed_items = $shed->find(sub { $_[0]->{char_id} eq $char->getCol('id') });
        last unless @$shed_items;

        # Hoarder check before entering market
        if ($sell_pol->{name} eq 'hoarder') {
            $transcript->log_event({
                type       => 'policy_skip_market',
                player     => $char_name,
                profile_id => $profile_id,
                reason     => 'hoarder',
                narrative  => sprintf("%s skipped market (hoarder policy).", $char_name),
            });
            last;
        }

        my $activity = $market->create(char_id => $char->getCol('id'));
        my $result = $activity->dispatch($char, 'begin');
        last unless $result->{view}{ok};

        # Check if we accept this customer
        if (!MagicMountain::Bot::SellPolicy::accept_customer($char, $activity->customer, $sell_pol)) {
            $activity->dispatch($char, 'send_away');
            $transcript->log_event({
                type       => 'policy_send_away',
                player     => $char_name,
                profile_id => $profile_id,
                reason     => $sell_pol->{name},
                narrative  => sprintf("%s sent away customer (%s policy).",
                    $char_name, $sell_pol->{name}),
            });
            last;
        }

        my $sell_params        = $sell_pol->{params} // {};
        my $max_irritation     = $sell_params->{max_irritation} // 3;
        my $max_pressure_state = $sell_params->{max_pressure_state} // 'mood_wary';
        my $n_mismatches       = 0;

        my $keep_offering = 1;
        while ($keep_offering) {
            my $current_items = $shed->find(sub { $_[0]->{char_id} eq $char->getCol('id') });
            last unless @$current_items;

            for my $item (@$current_items) {
                if (!MagicMountain::Bot::SellPolicy::should_offer_item($char, $item, $sell_pol)) {
                    $transcript->log_event({
                        type       => 'policy_skip_item',
                        player     => $char_name,
                        profile_id => $profile_id,
                        reason     => $sell_pol->{name},
                        value      => $item->getCol('decayed_value') // 0,
                        narrative  => sprintf("%s skipped item %s (value=%d, %s policy).",
                            $char_name, $item->getCol('artifact_id') // '?',
                            $item->getCol('decayed_value') // 0, $sell_pol->{name}),
                    });
                    next;
                }

                my $r = $activity->dispatch($char, 'offer', shed_item_id => $item->getCol('id'));
                my $view = $r->{view};
                $view->{player}{name} = $char_name;
                $view->{player}{profile_id} = $profile_id;

                if ($view->{result} eq 'sold') {
                    $keep_offering = 0;
                    last;
                }

                if ($view->{result} eq 'sold_more') {
                    if (_pressure_at_or_beyond($view->{pressure_state}, $max_pressure_state)) {
                        $activity->dispatch($char, 'send_away');
                        $keep_offering = 0;
                    } elsif ($view->{irritation} >= $max_irritation) {
                        $activity->dispatch($char, 'send_away');
                        $keep_offering = 0;
                    }
                    last;
                }

                if ($view->{result} eq 'counter_offer') {
                    my $decayed = $item->getCol('decayed_value') // $item->getCol('original_value') // 0;
                    if (MagicMountain::Bot::SellPolicy::should_accept_counter($char, $view->{counter_value}, $decayed, $sell_pol)) {
                        my $r2 = $activity->dispatch($char, 'accept_counter');
                        my $v2 = $r2->{view};
                        if ($v2->{result} eq 'sold_more') {
                            if (_pressure_at_or_beyond($v2->{pressure_state}, $max_pressure_state)) {
                                $activity->dispatch($char, 'send_away');
                                $keep_offering = 0;
                            } elsif ($v2->{irritation} >= $max_irritation) {
                                $activity->dispatch($char, 'send_away');
                                $keep_offering = 0;
                            }
                            last;
                        }
                        $keep_offering = 0;
                        last;
                    }
                    # Reject counter — try next item
                    $n_mismatches++;
                    if (!MagicMountain::Bot::SellPolicy::try_another($char, $view, $activity->customer, $sell_pol)) {
                        $transcript->log_event({
                            type        => 'policy_stop_offer',
                            player      => $char_name,
                            profile_id  => $profile_id,
                            reason      => $sell_pol->{name},
                            narrative   => sprintf("%s stopped offering (%s policy).",
                                $char_name, $sell_pol->{name}),
                        });
                        $keep_offering = 0;
                        last;
                    }
                    next;
                }

                if ($view->{result} eq 'over_budget') {
                    # Try a cheaper item — this one exceeded absolute
                    next;
                }

                if ($view->{result} eq 'customer_left') {
                    $keep_offering = 0;
                    last;
                }

                if ($view->{result} eq 'no_match') {
                    $n_mismatches++;
                    if (!MagicMountain::Bot::SellPolicy::try_another($char, $view, $activity->customer, $sell_pol)) {
                        $transcript->log_event({
                            type        => 'policy_stop_offer',
                            player      => $char_name,
                            profile_id  => $profile_id,
                            reason      => $sell_pol->{name},
                            narrative   => sprintf("%s stopped offering (%s policy).",
                                $char_name, $sell_pol->{name}),
                        });
                        $keep_offering = 0;
                        last;
                    }
                    next;
                }
            }
            # For loop exhausted all items — exit
            $keep_offering = 0;
        }
    }
}

1;
