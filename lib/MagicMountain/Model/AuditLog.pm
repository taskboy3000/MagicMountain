package MagicMountain::Model::AuditLog;
use Modern::Perl;
use Mojo::Base '-base', '-signatures';
use Mojo::JSON ('encode_json');
use File::Slurp qw(write_file);

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

1;
