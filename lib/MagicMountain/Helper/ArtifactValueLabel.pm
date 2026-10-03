package MagicMountain::Helper::ArtifactValueLabel;
use Mojo::Base '-base', '-signatures';
use YAML::XS qw(LoadFile);

has content_file => sub { die "content_file is required" };

our $gCache;

sub load ($self) {
    return $gCache if defined $gCache;

    my $file = $self->content_file;
    my $data = LoadFile($file);

    return $gCache = $data->{tiers} // [];
}

sub value_label ($self, $value=0) {
    $value //= 0;
    my $tiers = $self->load;
    for my $tier (@$tiers) {
        if ($value <= $tier->{max}) {
            return $tier->{label};
        }
    }

    # assume this is a very valuable item
    return $tiers->[-1]->{label};
}

1;
