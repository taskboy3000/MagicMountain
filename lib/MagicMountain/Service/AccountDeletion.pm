package MagicMountain::Service::AccountDeletion;
use Mojo::Base '-base', '-signatures';

has app => sub { die "app is required" };

sub delete_account ($self, $player_id) {
    $self->app->session_store->delete_by_player_id($player_id);

    my $chars = $self->app->characters;
    my $existing = $chars->find({ account_id => qr/^\Q$player_id\E$/ });
    for my $char (@$existing) {
        my $char_id = $char->getCol('id');
        $self->app->shed->load;
        my $shedItems = $self->app->shed->find({char_id => $char_id});
        for my $shedItem (@$shedItems) {
            $shedItem->delete;
        }
        $chars->delete($char_id);
    }

    $self->app->disposition->load;
    my $disps = $self->app->disposition->find(sub { $_[0]->{player_id} eq $player_id });
    for my $d (@$disps) {
        $self->app->disposition->delete($d->getCol('id'));
    }

    $self->app->season_records->load;
    my $recs = $self->app->season_records->find(sub { $_[0]->{player_id} eq $player_id });
    for my $r (@$recs) {
        $self->app->season_records->delete($r->getCol('id'));
    }

    $self->app->accounts->delete($player_id);

    $self->app->audit_log->log('account_deleted', player_id => $player_id);
}

1;
