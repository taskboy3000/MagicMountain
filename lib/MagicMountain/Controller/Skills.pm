package MagicMountain::Controller::Skills;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

use MagicMountain::Service::SkillTraining;

sub _build_skill_actions ($self, $skills, $scrap) {
    my $purchase_url = $self->url_for('skills_purchase');
    my @actions;
    for my $s (@$skills) {
        my $cur = $s->{current_level} // 0;
        my $max = $s->{max_level} // 3;
        my $at_max = $cur >= $max;
        my $next_cost = $at_max ? undef : ($s->{levels}[$cur]{cost} // undef);
        next unless !$at_max && defined $next_cost;
        push @actions, {
            label => "Upgrade ($next_cost)",
            attrs => {
                'data-action-url' => $purchase_url,
                'data-method'     => 'POST',
                class             => 'mm-btn mm-btn-primary buy-skill-btn',
                'data-skill-id'   => $s->{id},
                ($scrap < $next_cost ? (disabled => undef) : ()),
            },
        };
    }
    return \@actions;
}

sub index ($self) {
    my $char = $self->_require_character;
    return unless $char;

    my $svc = MagicMountain::Service::SkillTraining->new(app => $self->app);
    my $result = $svc->skill_list($char);
    my $actions = $self->_build_skill_actions($result->{skills}, $result->{scrap});

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(skills => $result->{skills}, scrap => $result->{scrap}, actions => $actions, purchase_url => $self->url_for('skills_purchase'));
        return $self->render('skills/training', layout => undef);
    }

    $self->render(json => { ok => 1, skills => $result->{skills}, _self => { actions => $actions } });
}

sub purchase ($self) {
    my $char = $self->_require_character;
    return unless $char;

    my $skill_id = $self->req->json->{skill_id};
    return $self->render(json => { ok => 0, error => 'skill_id required' }, status => 400) unless $skill_id;

    my $svc = MagicMountain::Service::SkillTraining->new(app => $self->app);
    my $result = $svc->purchase($char, $skill_id);

    if ($result->{ok}) {
        $self->_render_action({ view => $result }, 'purchase');
    } else {
        $self->render(json => $result, status => 400);
    }
}

1;
