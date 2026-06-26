package MagicMountain::Service::SkillTraining;
use Mojo::Base '-base', '-signatures';

has app => sub { die "app is required" };

sub purchase ($self, $char, $skill_id) {
    my $skills = $self->app->skills_data;
    my ($skill) = grep { $_->{id} eq $skill_id } @$skills;
    return { ok => 0, error => 'unknown skill' } unless $skill;

    my $col = 'skill_' . $skill_id;
    my $current_level = $char->getCol($col) // 0;
    return { ok => 0, error => 'already at max' } if $current_level >= $skill->{max_level};

    my $cost = $skill->{levels}[$current_level]{cost};
    return { ok => 0, error => 'not enough scrap' } if ($char->getCol('scrap') // 0) < $cost;

    $char->setCol('scrap', $char->getCol('scrap') - $cost);
    $char->setCol($col, $current_level + 1);
    $char->save;

    return {
        ok => 1,
        player => {
            action_points => $char->getCol('action_points'),
            scrap         => $char->getCol('scrap'),
            score         => $char->getCol('score'),
        },
    };
}

sub skill_list ($self, $char) {
    my $skills = $self->app->skills_data;
    for my $s (@$skills) {
        $s->{current_level} = $char->getCol('skill_' . $s->{id}) // 0;
    }

    my $scrap = $char->getCol('scrap') // 0;
    my @actions;

    for my $s (@$skills) {
        my $cur = $s->{current_level} // 0;
        my $max = $s->{max_level} // 3;
        my $at_max = $cur >= $max;
        my $next_cost = $at_max ? undef : ($s->{levels}[$cur]{cost} // undef);

        if (!$at_max && defined $next_cost) {
            my $disabled = $scrap < $next_cost;
            push @actions, {
                label => "Upgrade ($next_cost)",
                attrs => {
                    'data-action-url' => '/skills/purchase',
                    'data-method'     => 'POST',
                    class             => 'mm-btn mm-btn-primary buy-skill-btn',
                    'data-skill-id'   => $s->{id},
                    ($disabled ? (disabled => undef) : ()),
                },
            };
        }
    }

    return {
        skills  => $skills,
        scrap   => $scrap,
        actions => \@actions,
    };
}

1;
