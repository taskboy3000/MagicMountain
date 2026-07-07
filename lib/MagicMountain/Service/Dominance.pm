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
    return @parts ? join(', ', @parts) : 'Neutral market';
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

sub buyer_trait_biases ($self, $season) {
    my $climate = $season->getCol('faction_climate') // {};
    return $climate->{market}{buyer_trait_biases} // {};
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
            hint     => 'Expect richer customers, sharper tempers, and less stable finds.',
        },
        purifiers => {
            headline => 'A Wary Calm Settles Over the Yards',
            body     => 'Purifier patrols made their rounds before the first prospectors left camp. Fewer devices will reach the market unchecked, but those that do carry a heavier price.',
            hint     => 'Expect more volatile finds and buyers who know what they came for.',
        },
        revelationists => {
            headline => 'The Faithful Gather Before Dawn',
            body     => 'Signs were read in the bones of last night\'s fire. Pilgrims claim the Mountain called out in a language no scholar has catalogued. Strange artifacts have become a matter of conviction.',
            hint     => 'Expect unusual finds and buyers with very specific obsessions.',
        },
        faculty => {
            headline => 'Lanterns Burn Late in the Archive Tents',
            body     => 'Faculty surveyors were cataloguing before the salvage crews had their breakfast. The Mountain is being read like a manuscript today, and every find is another sentence.',
            hint     => 'Expect steadier artifacts, careful buyers, and fewer shortcuts.',
        },
        libremount => {
            headline => 'The Gates Open Without Permission',
            body     => 'LibreMount volunteers redistributed yesterday\'s surplus before the market could set prices. Access routes are clear, tolls have been cut, and the day\'s finds belong to whoever reaches them first.',
            hint     => 'Expect practical finds, fair moods, and lower top-end budgets.',
        },
    );
    return $MSGS{$fid} // {};
}

sub _crier_text ($self, $fid, $tier) {
    my $msg = $self->_crier_message($fid, $tier);
    return unless $msg->{headline};
    return sprintf("%s — %s", $msg->{headline}, $msg->{hint});
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
    return {} if $factor == 0;

    my $profile = $self->_profile_for($leader_id);
    my $climate = {
        day                 => $season->getCol('day'),
        dominant_faction    => $leader_id,
        dominant_faction_name => $self->_faction_name($leader_id),
        intensity           => $tier,
        intensity_label     => ucfirst($tier),
        dominance_margin    => $margin,
        prospecting         => {
            draw_biases              => $self->_scale_biases($profile->{draw_biases}, $factor),
            starting_instability_mod => int(($profile->{starting_instability_mod} // 0) * $factor),
        },
        market => {
            budget_delta        => int(($profile->{budget_delta} // 0) * $factor),
            mood_delta          => int(($profile->{mood_delta} // 0) * $factor),
            patience_delta      => int(($profile->{patience_delta} // 0) * $factor),
            risk_tolerance_delta => int(($profile->{risk_tolerance_delta} // 0) * $factor),
            buyer_trait_biases  => $self->_scale_biases($profile->{buyer_trait_biases}, $factor),
            budget_label        => ($profile->{budget_delta} // 0) >= 0 ? 'Richer buyers' : 'Tighter budgets',
            market_summary      => $self->_market_summary($profile, $factor),
        },
        town_crier => $self->_crier_message($leader_id, $tier),
        crier_text => $self->_crier_text($leader_id, $tier),
    };
    $season->setCol('faction_climate', $climate);
    $season->save;
    return $climate;
}

1;
