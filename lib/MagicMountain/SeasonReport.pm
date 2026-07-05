package MagicMountain::SeasonReport;
use Mojo::Base '-base', '-signatures';

has [qw(final_score final_scrap rank standing skills highlights season_label factions log standing_rows)];

sub build ($self) {
    my $hl  = $self->highlights // {};
    my $log = $self->log // sub {};

    my @sections;

    push @sections, { id => 'header', data => {} };

    my $tfi = $hl->{top_faction_influence} // 0;
    if ($tfi > 0) {
        my $top_faction = $self->_faction_name($hl->{top_faction});
        my $variant = 'dominated';
        $log->({ type => 'report_section', section => 'market', variant => $variant });
        push @sections, {
            id      => 'market',
            variant => $variant,
            data    => {
                top_faction => $top_faction,
                influence   => $tfi,
                competing   => $hl->{factions_competing} // 0,
            },
        };

        my @faction_ids = map { $_->{id} } @{ $self->factions // [] };
        my @pool = grep { $_ ne ($hl->{top_faction} // '') } @faction_ids;
        my $event_count = 1 + int(rand(2));
        my @event_types = qw(alliance war frustration merger stalemate);
        for my $ei (1 .. $event_count) {
            next if @pool < 2;
            my @shuffled = sort { rand() <=> rand() } @pool;
            my $evt = $event_types[int(rand(@event_types))];
            $log->({ type => 'report_section', section => 'faction_event', variant => $evt });
            push @sections, {
                id      => 'faction_event',
                variant => $evt,
                data    => {
                    faction_a => $self->_faction_name($shuffled[0]),
                    faction_b => $self->_faction_name($shuffled[1]),
                },
            };
        }
    } else {
        $log->({ type => 'report_section', section => 'market', variant => 'fragmented' });
        push @sections, {
            id      => 'market',
            variant => 'fragmented',
            data    => { competing => $hl->{factions_competing} // 0 },
        };
    }

    my $standing = $self->standing // {};
    my @standing_parts;
    for my $fid (sort { ($standing->{$b} // 0) <=> ($standing->{$a} // 0) } keys %$standing) {
        push @standing_parts, sprintf("%s (+%d)", $self->_faction_name($fid), $standing->{$fid});
    }

    if (@standing_parts) {
        my $count = scalar @standing_parts;
        my $total_sales = $hl->{total_sales} // 0;
        my $variant = $total_sales >= 5 ? 'significant' : ($total_sales >= 1 ? 'moderate' : 'minimal');
        $log->({ type => 'report_section', section => 'agent_impact', variant => $variant });
        push @sections, {
            id      => 'agent_impact',
            variant => $variant,
            data    => {
                standing_summary => join(', ', @standing_parts),
                standing_count   => $count,
            },
        };
    }

    my $rank = $self->rank // 0;
    my $rank_var = $rank <= 1 ? 'top' : ($rank <= 5 ? 'mid' : 'low');
    $log->({ type => 'report_section', section => 'rank', variant => $rank_var });
    push @sections, {
        id      => 'rank',
        variant => $rank_var,
        data    => { rank => $rank },
    };

    my $total_sales = $hl->{total_sales} // 0;
    if ($total_sales > 0) {
        $log->({ type => 'report_section', section => 'total_sales' });
        push @sections, { id => 'total_sales', data => { count => $total_sales } };
    }

    my $best_value = $hl->{top_sale_value} // 0;
    if ($best_value > 0) {
        $log->({ type => 'report_section', section => 'best_sale' });
        push @sections, {
            id   => 'best_sale',
            data => {
                value   => $best_value,
                faction => $self->_faction_name($hl->{top_sale_faction}),
            },
        };
    }

    my $evolved = $hl->{evolved_artifacts_sold} // 0;
    if ($evolved > 0) {
        $log->({ type => 'report_section', section => 'evolved_artifacts' });
        push @sections, { id => 'evolved_artifacts', data => { count => $evolved } };
    }

    my $clearance = $hl->{clearance_bonus} // 0;
    if ($clearance > 0) {
        $log->({ type => 'report_section', section => 'clearance' });
        push @sections, { id => 'clearance', data => { bonus => $clearance } };
    }

    push @sections, { id => 'closing', data => {} };

    return \@sections;
}

sub _faction_name ($self, $id) {
    return $id unless $id && $self->factions;
    for my $f (@{ $self->factions }) {
        return $f->{name} if $f->{id} eq $id;
    }
    return $id;
}

sub _faction_icon ($self, $id) {
    return unless $id && $self->factions;
    for my $f (@{ $self->factions }) {
        return '/images/' . $f->{icon} if $f->{id} eq $id && $f->{icon};
    }
    return;
}

sub build_standing_rows ($self) {
    my $standing = $self->standing // {};
    my @rows;
    for my $fid (sort keys %$standing) {
        push @rows, {
            id    => $fid,
            name  => $self->_faction_name($fid),
            icon  => $self->_faction_icon($fid),
            value => $standing->{$fid},
        };
    }
    return \@rows;
}

1;
