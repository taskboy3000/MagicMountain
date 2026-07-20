package MagicMountain::Controller::Shed;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub _pending_counter ($self, $char) {
    my $activity_id = $char->getCol('pending_activity_id') or return;
    my $activity = $self->app->market->get($activity_id) or return;
    my $customer = $activity->customer or return;
    return $customer->{pending_counter};
}

sub index ($self) {
    my $char = $self->_require_character;
    return unless $char;

    my $all = $self->app->shed->find(
        sub { $_[0]->{char_id} eq $char->getCol('id') }
    );

    my $filtered = _apply_filters($all, $self);

    my $pc = $self->_pending_counter($char);

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        my $type = $self->_active_activity_type($char);
        my $is_secondary = ($self->param('panel') || '') eq 'secondary';
        my $view_param = $self->param('view') || '';
        my $skill = $char->getCol('skill_prospecting') // 0;
        my $icon_base = $self->url_for('/images');
        my $banned_lookup = $self->app->pawn_calculator->banned_trait_lookup;
        my $items = _enriched_items($filtered, $is_secondary, $skill, $icon_base, $banned_lookup);
        my $pawn_context = ($type && $type eq 'pawn') || $view_param eq 'pawn';
        $self->stash(
            items                 => $items,
            market_active         => ($type && $type eq 'market') ? 1 : 0,
            pawn_active           => $pawn_context ? 1 : 0,
            offer_url             => $pawn_context ? $self->url_for('pawn_offer') : $self->url_for('market_offer'),
            climate_premium_traits => [ $type && $type eq 'pawn' ? () : sort keys %{ ($self->app->active_season ? $self->app->active_season->faction_climate : {})->{market}{buyer_trait_biases} // {} } ],
            show_trait_tags       => $skill >= 1 ? 1 : 0,
            pending_counter_item_id => $pc ? $pc->{item_id} : undef,
            pending_counter_value   => $pc ? $pc->{value} : undef,
            layout                => undef,
        );
        return $self->render('shed/ledger', layout => undef);
    }

    my $type = $self->_active_activity_type($char);
    my $market_active = ($type && $type eq 'market') ? 1 : 0;
    my $offer_url = $self->url_for('market_offer');
    my $icon_base = $self->url_for('/images');

    my $banned_lookup_json = $self->app->pawn_calculator->banned_trait_lookup;
    my $view_param = $self->param('view') || '';
    my $pawn_context = ($type && $type eq 'pawn') || $view_param eq 'pawn';
    my $offer_url_json = $pawn_context ? $self->url_for('pawn_offer') : $self->url_for('market_offer');
    $self->render(json => {
        ok    => 1,
        shed  => [ map { _item_view($_, $market_active, $offer_url_json, $icon_base, $pc, $banned_lookup_json) } @$filtered ],
        total => scalar @$all,
        count => scalar @$filtered,
        _self => { actions => [] },
    });
}

sub _item_view ($item, $market_active = 0, $offer_url = undef, $icon_base = '', $pending_counter = undef, $banned_lookup = {}) {
    my $behaviors = $item->getCol('behaviors') // [];
    my $banned = 0;
    for my $b (@$behaviors) {
        if ($banned_lookup->{$b}) { $banned = 1; last; }
    }
    my $v = {
        id                  => $item->getCol('id'),
        artifact_id         => $item->getCol('artifact_id'),
        condition           => $item->getCol('condition'),
        days_in_shed        => $item->getCol('days_in_shed'),
        original_value      => $item->getCol('original_value'),
        estimated_value_min => $item->getCol('estimated_value_min'),
        estimated_value_max => $item->getCol('estimated_value_max'),
        behaviors           => $behaviors,
        push_count          => $item->getCol('push_count'),
        stage               => $item->getCol('stage'),
        has_evolved         => $item->getCol('has_evolved') ? 1 : 0,
        banned              => $banned,
    };
    $v->{icon} = $icon_base . '/artifact_' . $v->{artifact_id} . '.svg';
    if ($market_active) {
        $v->{action_url} = $offer_url;
        $v->{method}     = 'POST';
        if ($pending_counter && $pending_counter->{item_id} eq $v->{id}) {
            $v->{disabled}         = 1;
            $v->{disabled_reason}  = sprintf('In negotiation — accept the %d-scrap counter or pick a different item', $pending_counter->{value});
        } elsif ($banned) {
            $v->{disabled}        = 1;
            $v->{disabled_reason} = 'Restricted by the dominant faction';
        }
    }
    return $v;
}

sub _enriched_items ($items, $is_secondary, $skill, $icon_base, $banned_lookup = {}) {
    my @out;
    for my $item (@$items) {
        my $aid = $item->getCol('artifact_id');
        my $behaviors = $item->getCol('behaviors') // [];
        my $banned = 0;
        for my $b (@$behaviors) {
            if ($banned_lookup->{$b}) { $banned = 1; last; }
        }
        push @out, {
            id          => $item->getCol('id'),
            label       => $aid,
            label_full  => $aid,
            icon        => $icon_base . '/artifact_' . $aid . '.svg',
            condition   => $item->getCol('condition'),
            tags        => $skill >= 1 ? join(', ', @$behaviors) : '-',
            value_label => $item->value_label,
            days        => $item->getCol('days_in_shed'),
            behaviors   => $behaviors,
            banned      => $banned,
        };
    }
    return \@out;
}

sub _apply_filters ($items, $c) {
    my @result = @$items;

    my $condition   = $c->param('condition');
    my $artifact_id = $c->param('artifact_id');
    my $behavior    = $c->param('behavior');
    my $min_value   = $c->param('min_value');
    my $max_value   = $c->param('max_value');
    my $sort        = $c->param('sort')    // 'value';
    my $order       = $c->param('order')   // 'desc';

    if (defined $condition) {
        @result = grep { ($_->getCol('condition') // '') eq $condition } @result;
    }
    if (defined $artifact_id) {
        @result = grep { ($_->getCol('artifact_id') // '') eq $artifact_id } @result;
    }
    if (defined $behavior) {
        @result = grep {
            my $b = $_->getCol('behaviors') // [];
            grep { $_ eq $behavior } @$b
        } @result;
    }
    if (defined $min_value) {
        @result = grep { ($_->getCol('estimated_value_min') // 0) >= $min_value } @result;
    }
    if (defined $max_value) {
        @result = grep { ($_->getCol('estimated_value_max') // 0) <= $max_value } @result;
    }

    my $sort_info = {
        value       => { field => 'estimated_value_min', numeric => 1 },
        age         => { field => 'days_in_shed',       numeric => 1 },
        artifact_id => { field => 'artifact_id',        numeric => 0 },
    }->{$sort} // { field => 'estimated_value_min', numeric => 1 };

    my $sf = $sort_info->{field};
    @result = sort {
        my $cmp = $sort_info->{numeric}
            ? ($a->getCol($sf) // 0) <=> ($b->getCol($sf) // 0)
            : ($a->getCol($sf) // '') cmp ($b->getCol($sf) // '');
        $order eq 'asc' ? $cmp : -$cmp;
    } @result;

    return \@result;
}

1;
