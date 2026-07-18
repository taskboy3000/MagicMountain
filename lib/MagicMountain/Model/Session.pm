package MagicMountain::Model::Session;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'player_id', 'last_active', 'node_number' ];
};

sub find_by_player_id ($self, $player_id) {
    my $found = $self->find(sub { $_[0]->{player_id} eq $player_id });
    return $found->[0];
}

sub is_expired ($self, $timeout_minutes) {
    my $now = time;
    my $last = $self->getCol('last_active') // 0;
    return ($now - $last) > ($timeout_minutes * 60);
}

sub touch ($self) {
    $self->setCol('last_active', time);
    $self->save;
}

sub active_count ($self, $timeout_minutes) {
    $self->load;
    my $cutoff = time - $timeout_minutes * 60;
    my $expired = $self->find(sub { ($_[0]->{last_active} // 0) < $cutoff });
    for my $s (@$expired) {
        $self->delete($s->getCol('id'));
    }
    my $active = $self->find(sub { ($_[0]->{last_active} // 0) >= $cutoff });
    return scalar @$active;
}

sub delete_by_player_id ($self, $player_id) {
    my $session = $self->find_by_player_id($player_id);
    if ($session) {
        $self->delete($session->getCol('id'));
    }
}

1;
