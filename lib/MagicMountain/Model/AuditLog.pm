package MagicMountain::Model::AuditLog;
use Modern::Perl;
use Mojo::Base '-base', '-signatures';
use Mojo::JSON qw(encode_json decode_json);
use File::Slurp qw(write_file read_file);

has file => sub { die "AuditLog requires a file path" };

sub log ($self, $event, %details) {
    my $entry = {
        timestamp => time,
        event     => $event,
        %details,
    };
    my $line = encode_json($entry) . "\n";
    write_file($self->file, { append => 1 }, $line);
}

sub all_entries ($self) {
    return [] unless -e $self->file;
    my $content = read_file($self->file);
    my @entries;
    for my $line (split /\n/, $content) {
        next unless $line;
        push @entries, decode_json($line);
    }
    return \@entries;
}

1;
