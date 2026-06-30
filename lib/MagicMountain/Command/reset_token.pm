package MagicMountain::Command::reset_token;
use Mojo::Base 'Mojolicious::Command', '-signatures';

has description => 'Reset an account token (prints new token to stdout)';
has usage       => "Usage: $0 reset-token --name <username>\n";

sub run ($self, @args) {
    my $name;
    while (@args) {
        my $arg = shift @args;
        if ($arg eq '--name' && @args) {
            $name = shift @args;
        }
    }

    die $self->usage unless $name;

    my $account = $self->app->accounts->find_by_username($name);
    die "Account '$name' not found.\n" unless $account;

    my $result = $self->app->auth_service->reset_token($account);
    say "New token for '$name': $result->{token}";
    say "New recovery code for '$name': $result->{recovery_code}";
    say "SAVE THIS — recovery code will not be shown again.";
}

1;
