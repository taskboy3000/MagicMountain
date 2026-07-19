package MagicMountain::Model::Character;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'name', 'account_id', 'season_id', 'score', 'scrap', 'action_points', 'action_points_max', 'pending_activity_id', 'faction_sales', 'standing', 'faction_snubs', 'snub_day', 'current_location', 'current_view', 'result', 'skill_prospecting', 'skill_upcycling', 'skill_selling', 'skill_smuggling', 'loyalty_visits_since', 'is_bot', 'bot_profile_id', 'seen_orientation', 'settings_muted', 'onboarding', 'pending_notices', 'turns_remaining', 'smuggle_reroll_used' ];
};

has app => undef;

sub create ($self, %params) {
    $params{loyalty_visits_since}                 //= 0;
    $params{faction_snubs}                        //= {};
    $params{seen_orientation}                     //= 0;
    $params{settings_muted}                       //= 0;
    $params{onboarding}                           //= 0;
    $params{pending_notices}                      //= 0;
    $params{skill_smuggling}                      //= 0;
    $params{smuggle_reroll_used}                  //= 0;
    my $obj = $self->SUPER::create(%params);
    $obj->app($self->app);
    return $obj;
}

sub get ($self, $id) {
    my $obj = $self->SUPER::get($id);
    $obj->app($self->app) if $obj;
    return $obj;
}

sub validate ($self, $col, $val) {
    if ($col eq 'score' && defined($val) && defined($self->getCol('score'))
        && $val < $self->getCol('score')) {
        die "invariant: score must never decrease";
    }
    if ($col eq 'scrap' && defined($val) && $val < 0) {
        die "invariant: scrap must be non-negative";
    }
    if ($col eq 'action_points' && defined($val)) {
        my $max = $self->getCol('action_points_max') // 15;
        die "invariant: action_points ($val) exceeds max ($max)" if $val > $max;
    }
    if ($col =~ /^skill_/ && defined($val) && ($val < 0 || $val > 4)) {
        die "invariant: $col must be 0-4";
    }
}

sub validate_save ($self) {
    my $ap = $self->row->{action_points};
    my $max = $self->row->{action_points_max} // 15;
    die "invariant: action_points ($ap) < 0" if defined $ap && $ap < 0;
    die "invariant: action_points ($ap) exceeds max ($max)" if defined $ap && $ap > $max;
    die "invariant: scrap < 0" if defined $self->row->{scrap} && $self->row->{scrap} < 0;
    die "invariant: score < 0" if defined $self->row->{score} && $self->row->{score} < 0;
    for my $sk (qw(skill_prospecting skill_upcycling skill_selling skill_smuggling)) {
        my $v = $self->row->{$sk};
        die "invariant: $sk ($v) out of range 0-4" if defined $v && ($v < 0 || $v > 4);
    }
}

sub add_scrap ($self, $n) {
    my $scrap = $self->getCol('scrap') + $n;
    $scrap = 0 if $scrap < 0;
    $self->setCol('scrap', $scrap);
}

sub add_score ($self, $n) {
    my $score = $self->getCol('score') + $n;
    $self->setCol('score', $score);
}

1;