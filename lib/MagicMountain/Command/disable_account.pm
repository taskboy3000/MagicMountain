package MagicMountain::Command::disable_account;
use Mojo::Base 'Mojolicious::Command', '-signatures';

has description => 'Disable a player account (prevents login)';
has usage       => "Usage: $0 disable-account --name <username>\n";

sub run ($self, @args) {
    my $name;
    while (@args) {
        my $arg = shift @args;
        if ($arg eq '--name' && @args) {
            $name = shift @args;
        }
    }

    die "Usage: $0 disable-account --name <username>\n" unless $name;

    my $account = $self->app->accounts->find_by_username($name);
    die "Account '$name' not found.\n" unless $account;

    $account->setCol('disabled', 1);
    $account->save;

    my $player_id = $account->getCol('id');
    $self->app->session_store->delete_by_player_id($player_id);

    $self->app->audit_log->log('account_disabled',
        player_id   => $player_id,
        player_name => $name,
    );

    say "Account '$name' disabled.";
    say "Any active sessions have been terminated.";
}

1;
