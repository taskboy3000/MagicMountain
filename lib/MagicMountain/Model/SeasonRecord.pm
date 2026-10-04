package MagicMountain::Model::SeasonRecord;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, qw(
        season_id player_id
        final_score final_scrap rank
        faction_standing_snapshot skills_snapshot
        story_highlights
    )];
};

# This method creates structures for the recap view
sub build_season_report ($self, $factions=[], $logger = undef) {
    my $rank = $self->getCol('rank') // 0;
    my $standing = $self->getCol('faction_standing_snapshot') // {};
    my $highlights = $self->getCol('story_highlights') // {};

    my $sections = [];
    my $standingRows = [];

    my $factionNameFromId = sub ($id) {
        return $id if !$id || !@$factions;
        for my $faction (@$factions) {
            if ($faction->{id} eq $id) { 
                return $faction->{name};
            }
        }
        return $id;
    };

    my $factionIconFromId = sub ($id) {
        return if !$id || !@$factions;
        for my $faction (@$factions) {
            if ($faction->{id} eq $id) { 
                # this *really* should use a viewer helper rather than use hardcoded paths
                return 'images/' . $faction->{icon};
            }
        }
        return;
    };

    push @$sections, { id => 'header', data => {} };

    my $tfi = $highlights->{top_faction_influence} // 0;
    if ($tfi > 0) {
        my $top_faction = $factionNameFromId->($highlights->{top_faction});
        my $variant = 'dominated';
        if (defined $logger) {
            $logger->({ type => 'report_section', section => 'market', variant => $variant });
        }
        push @$sections, {
            id      => 'market',
            variant => $variant,
            data    => {
                top_faction => $top_faction,
                influence   => $tfi,
                competing   => $highlights->{factions_competing} // 0,
            },
        };

        my @faction_ids = map { $_->{id} } @$factions;
        my @pool = grep { $_ ne ($highlights->{top_faction} // '') } @faction_ids;
        my $event_count = 1 + int(rand(2)); # Why is this random?
        my @event_types = qw(alliance war frustration merger stalemate);
        for my $ei (1 .. $event_count) {
            next if @pool < 2;
            my @shuffled = sort { rand() <=> rand() } @pool;
            my $evt = $event_types[int(rand(@event_types))];
            if (defined $logger) {
                $logger->({ type => 'report_section', section => 'faction_event', variant => $evt });
            }
            push @$sections, {
                id      => 'faction_event',
                variant => $evt,
                data    => {
                    faction_a => $factionNameFromId->($shuffled[0]),
                    faction_b => $factionNameFromId->($shuffled[1]),
                },
            };
        }
    } else {
        if (defined $logger) {
            $logger->({ type => 'report_section', section => 'market', variant => 'fragmented' });
        }
        push @$sections, {
            id      => 'market',
            variant => 'fragmented',
            data    => { competing => $highlights->{factions_competing} // 0 },
        };
    }

    my @standing_parts;
    for my $fid (sort { ($standing->{$b} // 0) <=> ($standing->{$a} // 0) } keys %$standing) {
        push @standing_parts, sprintf("%s (+%d)", $factionNameFromId->($fid), $standing->{$fid});
    }

    if (@standing_parts) {
        my $count = scalar @standing_parts;
        my $total_sales = $highlights->{total_sales} // 0;
        my $variant = $total_sales >= 5 ? 'significant' : ($total_sales >= 1 ? 'moderate' : 'minimal');
        if (defined $logger) {
            $logger->({ type => 'report_section', section => 'agent_impact', variant => $variant });
        }
        push @$sections, {
            id      => 'agent_impact',
            variant => $variant,
            data    => {
                standing_summary => join(', ', @standing_parts),
                standing_count   => $count,
            },
        };
    }

    # this is an existing bug
    # We want show the rank of the current player amoung all the current players
    # We need SeasonFinalize to compute 'players_competing' 
    my $seasonPlayers = 5;
    my $rank_var = $rank <= 1 ? 'top' : ($rank <= $seasonPlayers ? 'mid' : 'low');
    if (defined $logger) {
        $logger->({ type => 'report_section', section => 'rank', variant => $rank_var });
    }
    push @$sections, {
        id      => 'rank',
        variant => $rank_var,
        data    => { rank => $rank },
    };

    my $total_sales = $highlights->{total_sales} // 0;
    if ($total_sales > 0) {
        if (defined $logger) {
            $logger->({ type => 'report_section', section => 'total_sales' });
        }
        push @$sections, { id => 'total_sales', data => { count => $total_sales } };
    }

    my $best_value = $highlights->{top_sale_value} // 0;
    if ($best_value > 0) {
        if (defined $logger) {
            $logger->({ type => 'report_section', section => 'best_sale' });
        }
        push @$sections, {
            id   => 'best_sale',
            data => {
                value   => $best_value,
                faction => $factionNameFromId->($highlights->{top_sale_faction}),
            },
        };
    }

    my $evolved = $highlights->{evolved_artifacts_sold} // 0;
    if ($evolved > 0) {
        if (defined $logger) {
            $logger->({ type => 'report_section', section => 'evolved_artifacts' });
        }
        push @$sections, { id => 'evolved_artifacts', data => { count => $evolved } };
    }

    my $clearance = $highlights->{clearance_bonus} // 0;
    if ($clearance > 0) {
        if (defined $logger) {
            $logger->({ type => 'report_section', section => 'clearance' });
        }
        push @$sections, { id => 'clearance', data => { bonus => $clearance } };
    }

    push @$sections, { id => 'closing', data => {} };

    for my $factionId (sort keys %$standing) {
        push @$standingRows, {
            id => $factionId,
            name => $factionNameFromId->($factionId),
            icon => $factionIconFromId->($factionId),
            value => $standing->{$factionId} 
        };
    }

    return ($sections, $standingRows);
}

1;
