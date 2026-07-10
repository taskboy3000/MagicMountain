package MagicMountain::Model::BrokersCache;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, qw(season_id player_id artifact_id decayed_value behaviors char_name ts available) ];
};

sub log_entry ($self, %data) {
    $data{ts}        //= CORE::time;
    $data{available} //= 1;
    $data{behaviors} //= [];
    my $entry = $self->create(%data);
    $entry->save;
    return $entry;
}

sub draw_random ($self, %filters) {
    $self->load;
    my $all = $self->all;
    my @eligible;
    for my $id (keys %$all) {
        my $row = $all->{$id};
        next unless $row->{available};
        my $match = 1;
        for my $key (keys %filters) {
            if (defined $filters{$key}) {
                my $val = $row->{$key};
                if (ref $filters{$key} eq 'ARRAY' && ref $val eq 'ARRAY') {
                    my $found = grep { my $f = $_; grep { $_ eq $f } @$val } @{ $filters{$key} };
                    $match = 0 unless $found;
                } elsif ($val ne $filters{$key}) {
                    $match = 0;
                }
            }
        }
        push @eligible, $row if $match;
    }
    return undef unless @eligible;

    my $picked = $eligible[int(rand(scalar @eligible))];
    my $obj = $self->get($picked->{id});
    return undef unless $obj;
    $obj->setCol('available', 0);
    $obj->save;
    return $obj;
}

1;
