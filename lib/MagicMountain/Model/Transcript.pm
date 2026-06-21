package MagicMountain::Model::Transcript;
use Mojo::Base -base, -signatures;
use Mojo::JSON qw(encode_json);

has file => sub { die "file is required" };

sub log_event ($self, $event) {
    my $json = encode_json({ ts => time, %$event });
    my $fh = $self->_fh;
    print $fh "$json\n";
}

sub _fh ($self) {
    $self->{_fh} //= do {
        open my $fh, '>>:unix', $self->file
            or die "cannot open transcript $self->file: $!";
        $fh;
    };
}

sub DESTROY ($self) {
    close $self->{_fh} if $self->{_fh};
}

1;
