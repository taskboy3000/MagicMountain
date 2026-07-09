package MagicMountain::Controller::Skills;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

use MagicMountain::Service::SkillTraining;

sub index ($self) {
    my $char = $self->_require_character;
    return unless $char;

    my $svc = MagicMountain::Service::SkillTraining->new(app => $self->app);
    my $result = $svc->skill_list($char);

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(skills => $result->{skills}, scrap => $result->{scrap}, actions => $result->{actions}, purchase_url => $self->url_for('skills_purchase'));
        return $self->render('skills/training', layout => undef);
    }

    $self->render(json => { ok => 1, skills => $result->{skills}, _self => { actions => $result->{actions} } });
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
