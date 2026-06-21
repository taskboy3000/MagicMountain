package MagicMountain::Controller::Skills;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub index ($self) {
    my $char = $self->_require_character;
    return unless $char;

    my $skills = $self->app->skills_data;
    for my $s (@$skills) {
        $s->{current_level} = $char->getCol('skill_' . $s->{id}) // 0;
    }

    $self->render(json => { ok => 1, skills => $skills });
}

sub purchase ($self) {
    my $char = $self->_require_character;
    return unless $char;

    my $skill_id = $self->req->json->{skill_id} or die "skill_id required";

    my $skills = $self->app->skills_data;
    my ($skill) = grep { $_->{id} eq $skill_id } @$skills;
    die "unknown skill: $skill_id" unless $skill;

    my $col = 'skill_' . $skill_id;
    my $current = $char->getCol($col) // 0;
    die "skill $skill_id already at max" if $current >= $skill->{max_level};

    my $cost = $skill->{levels}[$current]{cost};
    die "not enough scrap" if ($char->getCol('scrap') // 0) < $cost;

    $char->setCol('scrap', $char->getCol('scrap') - $cost);
    $char->setCol($col, $current + 1);
    $char->save;

    $self->render(json => {
        ok     => 1,
        player => {
            action_points => $char->getCol('action_points'),
            scrap         => $char->getCol('scrap'),
            score         => $char->getCol('score'),
        },
    });
}

1;
