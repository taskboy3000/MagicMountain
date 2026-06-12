package MagicMountain::Model::Session;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, 'player_id', 'last_active' ];
};

sub find_by_player_id ($self, $player_id) {
    $self->load;
    for my $id (keys %{$self->table}) {
        my $row = $self->table->{$id};
        if (($row->{player_id} // '') eq $player_id) {
            return $self->new(
                file  => $self->file,
                log   => $self->log,
                table => $self->table,
                row   => { %{ $row } },
            );
        }
    }
    return;
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

sub delete_by_player_id ($self, $player_id) {
    my $session = $self->find_by_player_id($player_id);
    if ($session) {
        $self->delete($session->getCol('id'));
    }
}

1;
