package MagicMountain::Artifact;
use Mojo::Base '-base', '-signatures';

has [qw(id intro signal stage instability max_instability value icon)];

# Fix me later
sub stage_badge_css ($self) {
    my %map = (stable => 'mm-badge-green', strained => 'mm-badge-amber', unstable => 'mm-badge-red');
    return $map{ $self->stage // '' } // 'mm-badge-green';
}

sub TO_JSON ($self) {
    return {
        id              => $self->id,
        icon            => $self->icon,
        stage           => $self->stage,
        value           => $self->value, 
        signal          => $self->signal // '',
        intro           => $self->intro // '',
        instability     => $self->instability,
        max_instability => $self->max_instability,
    };
}

1;
