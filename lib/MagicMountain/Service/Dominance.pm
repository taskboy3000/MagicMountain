package MagicMountain::Service::Dominance;
use Mojo::Base '-base', '-signatures';

has app => sub { die "app is required" };

has profiles => sub ($self) {
    my $factions = $self->app->factions_data // [];
    my %profiles;
    for my $f (@$factions) {
        next unless $f->{climate};
        $profiles{$f->{id}} = $f->{climate};
        $profiles{$f->{id}}{name} = $f->{name};
    }
    return \%profiles;
};

sub _profile_for ($self, $fid) {
    return $self->profiles->{$fid} // {};
}

sub _faction_name ($self, $fid) {
    return ($self->profiles->{$fid}{name}) // $fid;
}

sub _scale_biases ($self, $biases, $factor) {
    return {} unless $biases && $factor != 0;
    return $biases if $factor == 1;
    my %scaled = map { $_ => $biases->{$_} * $factor } keys %$biases;
    return \%scaled;
}

sub _market_summary ($self, $profile, $factor) {
    my @parts;
    push @parts, 'Richer buyers'   if ($profile->{budget_delta} // 0) * $factor > 0;
    push @parts, 'Tighter budgets' if ($profile->{budget_delta} // 0) * $factor < 0;
    push @parts, 'Shorter tempers' if ($profile->{patience_delta} // 0) * $factor < 0;
    push @parts, 'More patient'    if ($profile->{patience_delta} // 0) * $factor > 0;
    push @parts, 'Volatile moods'  if abs($profile->{mood_delta} // 0) * $factor >= 1;
    push @parts, 'Faster sellout'  if ($profile->{appetite_delta} // 0) * $factor < 0;
    push @parts, 'Slower sellout'  if ($profile->{appetite_delta} // 0) * $factor > 0;
    return @parts ? join(', ', @parts) : 'Neutral market';
}

sub _classify_trait_effects ($self, $biases) {
    my $threshold = 0.15;
    my ($strong_boost, $moderate_boost);
    my ($strong_suppress, $moderate_suppress);

    for my $trait (keys %$biases) {
        my $deviation = abs($biases->{$trait} - 1);
        next if $deviation < $threshold;

        if ($biases->{$trait} > 1) {
            if ($deviation >= 0.30) {
                push @$strong_boost, { trait => $trait, deviation => $deviation };
            } else {
                push @$moderate_boost, { trait => $trait, deviation => $deviation };
            }
        } else {
            if ($deviation >= 0.30) {
                push @$strong_suppress, { trait => $trait, deviation => $deviation };
            } else {
                push @$moderate_suppress, { trait => $trait, deviation => $deviation };
            }
        }
    }

    my $_sort = sub { sort { $b->{deviation} <=> $a->{deviation} || $a->{trait} cmp $b->{trait} } @_ };

    return {
        boost => {
            strong   => $strong_boost    ? [$_sort->(@$strong_boost)]    : [],
            moderate => $moderate_boost  ? [$_sort->(@$moderate_boost)]  : [],
        },
        suppress => {
            strong   => $strong_suppress ? [$_sort->(@$strong_suppress)] : [],
            moderate => $moderate_suppress ? [$_sort->(@$moderate_suppress)] : [],
        },
    };
}

sub _format_trait_band ($self, $label, $traits) {
    return '' unless $traits && @$traits;
    my $names = join(', ', map { $_->{trait} } @$traits);
    return "$label: $names. ";
}

sub _format_instability ($self, $mod) {
    return 'More unstable than usual. ' if $mod > 0;
    return 'More stable than usual. '   if $mod < 0;
    return '';
}

sub _finds_summary ($self, $biases, $inst_mod) {
    my $classified = $self->_classify_trait_effects($biases);
    my $text = '';

    $text .= $self->_format_trait_band('Strong boost', $classified->{boost}{strong});
    $text .= $self->_format_trait_band('Moderate boost', $classified->{boost}{moderate});
    $text .= $self->_format_trait_band('Suppressed', $classified->{suppress}{strong});
    $text .= $self->_format_trait_band('Suppressed', $classified->{suppress}{moderate});
    $text .= $self->_format_instability($inst_mod);

    $text =~ s/^\s+//;
    $text =~ s/\s+$//;
    return $text || 'No meaningful climate effect on prospecting today.';
}

sub intensity_tier ($self, $margin) {
    return 'contested'  if $margin <= 4;
    return 'leading'    if $margin <= 12;
    return 'strong'     if $margin <= 24;
    return 'dominant';
}

sub climate_intensity_factor ($self, $tier) {
    return 0   if $tier eq 'contested';
    return 1   if $tier eq 'leading';
    return 1.5 if $tier eq 'strong';
    return 2;
}

sub dominant_faction ($self, $season) {
    my $climate = $season->getCol('faction_climate') // {};
    return $climate->{dominant_faction};
}

sub leader_influence ($self, $season) {
    my $fs = $season->getCol('faction_state') // return 0;
    my @rank = sort { $fs->{$b}{influence} // 0 <=> $fs->{$a}{influence} // 0 } keys %$fs;
    return 0 unless @rank;
    return $fs->{$rank[0]}{influence} // 0;
}

sub influence_ratio ($self, $season, $fid) {
    my $leader = $self->leader_influence($season);
    return 0 unless $leader > 0;
    my $fs = $season->getCol('faction_state') // {};
    return ($fs->{$fid}{influence} // 0) / $leader;
}

sub is_dominant ($self, $season, $fid) {
    my $dom = $self->dominant_faction($season);
    return defined $dom && $dom eq $fid;
}

sub draw_biases ($self, $season) {
    my $climate = $season->getCol('faction_climate') // {};
    return $climate->{prospecting}{draw_biases} // {};
}

sub starting_instability_mod ($self, $season) {
    my $climate = $season->getCol('faction_climate') // {};
    return $climate->{prospecting}{starting_instability_mod} // 0;
}

sub budget_delta ($self, $season) {
    my $climate = $season->getCol('faction_climate') // {};
    return $climate->{market}{budget_delta} // 0;
}

sub mood_delta ($self, $season) {
    my $climate = $season->getCol('faction_climate') // {};
    return $climate->{market}{mood_delta} // 0;
}

sub patience_delta ($self, $season) {
    my $climate = $season->getCol('faction_climate') // {};
    return $climate->{market}{patience_delta} // 0;
}

sub risk_tolerance_delta ($self, $season) {
    my $climate = $season->getCol('faction_climate') // {};
    return $climate->{market}{risk_tolerance_delta} // 0;
}

sub appetite_delta ($self, $season) {
    my $climate = $season->getCol('faction_climate') // {};
    return $climate->{market}{appetite_delta} // 0;
}

sub buyer_trait_biases ($self, $season) {
    my $climate = $season->getCol('faction_climate') // {};
    return $climate->{market}{buyer_trait_biases} // {};
}

sub ranked_factions ($self, $season) {
    my $fs = $season->getCol('faction_state') // return [];
    my @rank = sort { ($fs->{$b}{influence} || 0) <=> ($fs->{$a}{influence} || 0) } keys %$fs;
    my $leader = @rank ? ($fs->{$rank[0]}{influence} // 1) : 1;
    my @result;
    for my $i (0 .. $#rank) {
        push @result, {
            faction_id => $rank[$i],
            rank       => $i + 1,
            influence  => $fs->{$rank[$i]}{influence} // 0,
            ratio      => ($fs->{$rank[$i]}{influence} // 0) / $leader,
        };
    }
    return \@result;
}

sub _build_shape ($self, $rows, $width) {
    my @shape;
    for my $r (0 .. $rows - 1) {
        my $progress = $rows == 1 ? 1 : $r / ($rows - 1);
        my $filled = 1 + int($progress * ($width - 1));
        my $padding = $width - $filled;
        my $left_pad = int($padding / 2);
        my $right_pad = $padding - $left_pad;
        my @row = (0) x $left_pad;
        push @row, (1) x $filled;
        push @row, (0) x $right_pad;
        push @shape, \@row;
    }
    return \@shape;
}

sub faction_positions ($self, $season, $total_rows = 22) {
    my $ranked = $self->ranked_factions($season);
    my $num = scalar @$ranked;
    return [] unless $num;

    my @positions;
    for my $i (0 .. $#$ranked) {
        my $f = $ranked->[$i];
        my $row;
        if ($i == 0) {
            $row = 1;
        } else {
            $row = 1 + int((1 - ($f->{ratio} // 0)) * ($total_rows - 1) + 0.5);
            $row = $total_rows if $row > $total_rows;
            $row = 2 if $row < 2;
        }
        push @positions, { %$f, row_offset => $row };
    }

    my $use_proportional = 1;
    for my $i (1 .. $#positions) {
        if ($positions[$i]{row_offset} - $positions[$i-1]{row_offset} < 2) {
            $use_proportional = 0;
            last;
        }
    }

    if (!$use_proportional) {
        my $step = ($total_rows - 1) / ($num - 1);
        for my $i (0 .. $#positions) {
            $positions[$i]{row_offset} = 1 + int($i * $step + 0.5);
        }
    }

    return \@positions;
}

sub _build_raster ($self, $tier, $shape) {
    my %dist = (
        contested => [0.25, 0.35, 0.40],
        leading   => [0.45, 0.35, 0.20],
        strong    => [0.70, 0.25, 0.05],
        dominant  => [0.90, 0.10, 0.00],
    );
    my $d = $dist{$tier} || $dist{contested};
    my @rows;
    for my $row (@$shape) {
        my @chars;
        for my $cell (@$row) {
            if (!$cell) { push @chars, ' '; next; }
            my $r = rand;
            push @chars,
                $r < $d->[0] ? "\x{2588}"
              : $r < $d->[0] + $d->[1] ? "\x{2593}"
              : "\x{2591}";
        }
        push @rows, join('', @chars);
    }
    return \@rows;
}

sub saturation_floor_active ($self, $season, $fid, $trait) {
    my $climate = $season->getCol('faction_climate') // {};
    return 0 unless $climate->{dominant_faction};
    return 0 unless $climate->{dominant_faction} eq $fid;
    my $profile = $self->_profile_for($fid);
    return 0 unless $profile->{draw_biases}->{$trait} && $profile->{draw_biases}->{$trait} > 1;
    return 1;
}

sub _crier_message ($self, $fid, $tier) {
    my %MSGS = (
        syndicate => {
            headline => 'The Roads Belong to Fast Money',
            body     => 'The Syndicate\'s runners were outside the east gate before sunrise, counting crates before the prospectors came down. Buyers are flush today, but nobody is waiting politely.',
            hint     => 'Expect richer customers, sharper tempers, and shorter attention spans across the market.',
        },
        purifiers => {
            headline => 'A Wary Calm Settles Over the Yards',
            body     => 'Purifier patrols made their rounds before the first prospectors left camp. Fewer devices will reach the market unchecked, but those that do carry a heavier price.',
            hint     => 'Expect more volatile finds, irritable buyers, and restricted trade channels.',
        },
        revelationists => {
            headline => 'The Faithful Gather Before Dawn',
            body     => 'Signs were read in the bones of last night\'s fire. Pilgrims claim the Mountain called out in a language no scholar has catalogued. Strange artifacts have become a matter of conviction.',
            hint     => 'Expect unusual finds, patient buyers, and mundane items refused at the bazaar.',
        },
        faculty => {
            headline => 'Lanterns Burn Late in the Archive Tents',
            body     => 'Faculty surveyors were cataloguing before the salvage crews had their breakfast. The Mountain is being read like a manuscript today, and every find is another sentence.',
            hint     => 'Expect scholarly premiums on rare traits, but tighter budgets across the board.',
        },
        libremount => {
            headline => 'The Gates Open Without Permission',
            body     => 'LibreMount volunteers redistributed yesterday\'s surplus before the market could set prices. Access routes are clear, tolls have been cut, and the day\'s finds belong to whoever reaches them first.',
            hint     => 'Expect practical finds, fair moods, and no trait premiums — pure value trading.',
        },
    );
    return $MSGS{$fid} // {};
}

sub _crier_text ($self, $fid, $tier, $profile) {
    my $msg = $self->_crier_message($fid, $tier);
    return unless $msg->{headline};
    my $sell = $self->_sell_side_hint($profile);
    if ($sell) {
        return sprintf("%s — %s", $msg->{headline}, $sell);
    }
    my @FLAVOR = (
        'Artifact values drift with the mountain\'s cycles. No pattern holds for long.',
        'Faction buyers survey the Bazaar in silence. Their intentions are their own.',
        'The mountain\'s voice is indistinct today. Listen to the scrap.',
        'Competing interests blur the market\'s shape. Trade with care.',
        'The Bazaar breathes. Currents shift beneath the surface.',
        'A quiet day on the mountain. Salvage speaks for itself.',
    );
    return sprintf("%s — %s", $msg->{headline}, $FLAVOR[ int(rand(scalar @FLAVOR)) ]);
}

sub _sell_side_hint ($self, $profile) {
    my @parts;
    my $biases = $profile->{buyer_trait_biases} // {};
    if (keys %$biases) {
        push @parts, 'Paying premium for: ' . join(', ', sort keys %$biases);
    }
    my $banned = $profile->{banned_traits} // [];
    if (@$banned) {
        push @parts, 'Restricted: ' . join(', ', @$banned);
    }
    return join('; ', @parts);
}

sub _build_mountain_data ($self, $season, $tier) {
    my $ranked = $self->faction_positions($season);
    my $lowest = 1;
    for my $r (@$ranked) {
        $lowest = $r->{row_offset} if $r->{row_offset} > $lowest;
    }
    my $mountain_height = $lowest < 10 ? 10 : $lowest;
    if ($mountain_height != 22) {
        $ranked = $self->faction_positions($season, $mountain_height);
        $lowest = 1;
        for my $r (@$ranked) {
            $lowest = $r->{row_offset} if $r->{row_offset} > $lowest;
        }
        $mountain_height = $lowest < 10 ? 10 : $lowest;
    }
    my $shape = $self->_build_shape($mountain_height, 19);
    my $raster = $self->_build_raster($tier, $shape);
    return {
        mountain_positions => $ranked,
        mountain_height    => $mountain_height,
        mountain_raster    => $raster,
    };
}

sub ensure_mountain_data ($self, $season) {
    my $fc   = $season->getCol('faction_climate') // {};
    my $fs   = $season->getCol('faction_state') // return;
    my @rank = map { $_->[0] } sort { $b->[1] <=> $a->[1] } map { [ $_, $fs->{$_}{influence} // 0 ] } keys %$fs;
    return if @rank < 2;
    my $leader_id = $rank[0];
    return if $fc->{dominant_faction} && $fc->{dominant_faction} eq $leader_id && $fc->{mountain_positions};
    my $runner_id = $rank[1];
    my $margin    = ($fs->{$leader_id}{influence} // 0) - ($fs->{$runner_id}{influence} // 0);
    my $tier      = $self->intensity_tier($margin);
    my $mountain  = $self->_build_mountain_data($season, $tier);
    $fc->{day}                  = $season->getCol('day');
    $fc->{dominant_faction}     = $leader_id;
    $fc->{dominant_faction_name} = $self->_faction_name($leader_id);
    $fc->{dominance_margin}     = $margin;
    $fc->{intensity}            = $tier;
    $fc->{intensity_label}      = ucfirst($tier);
    $fc->{mountain_positions}   = $mountain->{mountain_positions};
    $fc->{mountain_height}      = $mountain->{mountain_height};
    $fc->{mountain_raster}      = $mountain->{mountain_raster};
    $season->setCol('faction_climate', $fc);
    $season->save;
}

sub calculate_climate ($self, $season) {
    my $fs = $season->getCol('faction_state') // return {};
    my @rank = sort { $fs->{$b}{influence} // 0 <=> $fs->{$a}{influence} // 0 } keys %$fs;
    return {} if @rank < 2;

    my $leader_id = $rank[0];
    my $runner_id = $rank[1];
    my $margin    = ($fs->{$leader_id}{influence} // 0) - ($fs->{$runner_id}{influence} // 0);
    my $tier      = $self->intensity_tier($margin);
    my $factor    = $self->climate_intensity_factor($tier);

    my $profile  = $self->_profile_for($leader_id);
    my $scaled_biases   = $self->_scale_biases($profile->{draw_biases}, $factor);
    my $scaled_inst_mod = int(($profile->{starting_instability_mod} // 0) * $factor);
    my $finds_summary   = $self->_finds_summary($scaled_biases, $scaled_inst_mod);

    my $climate = {
        day                 => $season->getCol('day'),
        dominant_faction    => $leader_id,
        dominant_faction_name => $self->_faction_name($leader_id),
        banned_traits       => $factor > 0 ? ($profile->{banned_traits} // []) : [],
        intensity           => $tier,
        intensity_label     => ucfirst($tier),
        dominance_margin    => $margin,
        prospecting         => {
            draw_biases              => $scaled_biases,
            starting_instability_mod => $scaled_inst_mod,
        },
        market => {
            budget_delta        => int(($profile->{budget_delta} // 0) * $factor),
            mood_delta          => int(($profile->{mood_delta} // 0) * $factor),
            patience_delta      => int(($profile->{patience_delta} // 0) * $factor),
            risk_tolerance_delta => int(($profile->{risk_tolerance_delta} // 0) * $factor),
            appetite_delta      => int(($profile->{appetite_delta} // 0) * $factor),
            buyer_trait_biases  => $self->_scale_biases($profile->{buyer_trait_biases}, $factor),
            budget_label        => ($profile->{budget_delta} // 0) >= 0 ? 'Richer buyers' : 'Tighter budgets',
            market_summary      => $self->_market_summary($profile, $factor),
        },
        town_crier          => $self->_crier_message($leader_id, $tier),
        crier_text          => $self->_crier_text($leader_id, $tier, $profile),
        finds_summary       => $finds_summary,
        has_meaningful_finds => $finds_summary ne 'No meaningful climate effect on prospecting today.',
    };

    my $mountain = $self->_build_mountain_data($season, $tier);
    $climate->{mountain_positions} = $mountain->{mountain_positions};
    $climate->{mountain_height}    = $mountain->{mountain_height};
    $climate->{mountain_raster}    = $mountain->{mountain_raster};
    $season->setCol('faction_climate', $climate);
    $season->save;
    return $climate;
}

1;
