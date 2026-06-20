package MagicMountain::Command::create_account;
use Mojo::Base 'Mojolicious::Command', '-signatures';

has description => 'Create a new player account';
has usage       => "Usage: $0 create-account --name <display_name>\n";

sub run ($self, @args) {
    my $name;
    while (@args) {
        my $arg = shift @args;
        if ($arg eq '--name' && @args) {
            $name = shift @args;
        }
    }

    die "Usage: $0 create-account --name <username>\n" unless $name;

    my $account = $self->app->accounts->create(username => $name);
    $account->save;

    say "Account created:";
    say "  player_id:    " . $account->getCol('id');
    say "  display_name: " . $account->getCol('username');
}

1;
