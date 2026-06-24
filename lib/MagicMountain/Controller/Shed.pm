package MagicMountain::Controller::Shed;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub index ($self) {
    my $char = $self->_require_character;
    return unless $char;

    my $all = $self->app->shed->find(
        sub { $_[0]->{char_id} eq $char->getCol('id') }
    );

    my $filtered = _apply_filters($all, $self);

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        my $type = $self->_active_activity_type($char);
        $self->stash(
            items         => $filtered,
            market_active => ($type && $type eq 'market') ? 1 : 0,
            layout        => undef,
        );
        return $self->render('shed/ledger', layout => undef);
    }

    my $type = $self->_active_activity_type($char);
    my $market_active = ($type && $type eq 'market') ? 1 : 0;

    $self->render(json => {
        ok    => 1,
        shed  => [ map { _item_view($_, $market_active) } @$filtered ],
        total => scalar @$all,
        count => scalar @$filtered,
        _self => { actions => [] },
    });
}

sub _item_view ($item, $market_active = 0) {
    my $v = {
        id                  => $item->getCol('id'),
        artifact_id         => $item->getCol('artifact_id'),
        condition           => $item->getCol('condition'),
        days_in_shed        => $item->getCol('days_in_shed'),
        original_value      => $item->getCol('original_value'),
        estimated_value_min => $item->getCol('estimated_value_min'),
        estimated_value_max => $item->getCol('estimated_value_max'),
        behaviors           => $item->getCol('behaviors'),
        push_count          => $item->getCol('push_count'),
        stage               => $item->getCol('stage'),
        has_evolved         => $item->getCol('has_evolved') ? 1 : 0,
    };
    if ($market_active) {
        $v->{action_url} = '/market/offer';
        $v->{method}     = 'POST';
    }
    return $v;
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
