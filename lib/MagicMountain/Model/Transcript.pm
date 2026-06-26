package MagicMountain::Model::Transcript;
use Mojo::Base -base, -signatures;
use Mojo::JSON qw(encode_json decode_json);
use File::Slurp qw(read_file);

has file => sub { die "file is required" };

sub log_event ($self, $event) {
    my $json = encode_json({ ts => time, %$event });
    my $fh = $self->_fh;
    print $fh "$json\n";
}

sub all_events ($self) {
    return [] unless -e $self->file;
    my $content = read_file($self->file);
    my @events;
    for my $line (split /\n/, $content) {
        next unless $line;
        push @events, decode_json($line);
    }
    return \@events;
}

sub _fh ($self) {
    $self->{_fh} //= do {
        open my $fh, '>>:unix', $self->file
            or die "cannot open transcript $self->file: $!";
        $fh;
    };
}

sub export_to ($self, $path) {
    my $events = $self->all_events;
    open my $fh, '>:unix', $path or die "cannot write $path: $!";
    for my $e (@$events) {
        print $fh encode_json($e) . "\n";
    }
    close $fh;
}

sub DESTROY ($self) {
    close $self->{_fh} if $self->{_fh};
}

1;
