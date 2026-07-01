package MagicMountain::Controller::OnboardingNotice;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

use constant {
    BIT_BAZAAR   => 1,
    BIT_FACTIONS => 2,
    BIT_SKILLS   => 4,
    BIT_INTEL    => 8,
};

my %BITS = (
    bazaar   => BIT_BAZAAR,
    factions => BIT_FACTIONS,
    skills   => BIT_SKILLS,
    pvp      => BIT_INTEL,
);

my %LABEL = (
    bazaar   => 'BAZAAR ACCESS',
    factions => 'FACTIONS',
    skills   => 'CERTIFICATIONS',
    pvp      => 'RIVAL INTEL',
);

my %FLAVOR = (
    bazaar   => 'Your shed contains recoverable artifacts. The Bazaar is now available — visit to sell to faction buyers.',
    factions => 'Your market activity has attracted faction attention. Monitor faction relationships in the FACTIONS panel.',
    skills   => 'You have sufficient scrap to purchase skill modules. CERTS can improve prospecting, push stability, and negotiation.',
    pvp      => 'Rival intel is now accessible. Apply pressure to competing operators through the INTEL panel.',
);

sub show ($self) {
    my $char   = $self->_require_character or return;
    my $notice = $self->param('notice') or return $self->render(text => '', status => 400);
    my $bit    = $BITS{$notice} or return $self->render(text => '', status => 400);

    my $pending = $char->getCol('pending_notices') // 0;
    return $self->render(text => '', status => 204) unless $pending & $bit;

    my $format = $self->param('_format');
    if ($format && $format eq 'fragment') {
        $self->stash(
            notice_id => $notice,
            label     => $LABEL{$notice},
            flavor    => $FLAVOR{$notice},
        );
        return $self->render('onboarding/notice', layout => undef);
    }
    $self->render(json => { ok => 1, notice => $notice });
}

sub dismiss ($self) {
    my $char   = $self->_require_character or return;
    my $notice = $self->req->json->{notice_id} or return $self->render(json => { ok => 0, error => 'notice_id required' }, status => 400);
    my $bit    = $BITS{$notice} or return $self->render(json => { ok => 0, error => 'unknown notice' }, status => 400);

    my $pending = $char->getCol('pending_notices') // 0;
    $char->setCol('pending_notices', $pending & ~$bit);
    $char->save;

    $self->render(json => { ok => 1, notice_dismissed => $notice });
}

1;
