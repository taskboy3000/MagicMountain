package MagicMountain::Command::delete_account;
use Mojo::Base 'Mojolicious::Command', '-signatures';

has description => 'Delete a player account and all associated data';
has usage       => "Usage: $0 delete-account --name <username>\n";

sub run ($self, @args) {
    my $name;
    while (@args) {
        my $arg = shift @args;
        if ($arg eq '--name' && @args) {
            $name = shift @args;
        }
    }

    die "Usage: $0 delete-account --name <username>\n" unless $name;

    my $account = $self->app->accounts->find_by_username($name);
    die "Account '$name' not found.\n" unless $account;

    my $player_id = $account->getCol('id');

    $self->app->session_store->delete_by_player_id($player_id);

    my $chars = $self->app->characters;
    my $existing = $chars->find({ account_id => qr/^\Q$player_id\E$/ });
    for my $char (@$existing) {
        $chars->delete($char->getCol('id'));
    }

    $self->app->accounts->delete($player_id);

    $self->app->audit_log->log('account_deleted',
        player_id   => $player_id,
        player_name => $name,
    );

    say "Account '$name' deleted.";
    say "Associated characters and sessions have been removed.";
}

1;
