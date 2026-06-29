package MagicMountain::Command::migrate_tokens;
use Mojo::Base 'Mojolicious::Command', '-signatures';

has description => 'Assign tokens to all accounts that lack them';
has usage       => "Usage: $0 migrate-tokens\n";

sub run ($self, @args) {
    my $auth = $self->app->auth_service;
    $self->app->accounts->load;

    my $count = 0;
    for my $id (keys %{ $self->app->accounts->all }) {
        my $acct = $self->app->accounts->get($id);
        next if $acct->getCol('token_hash');
        my $token = $auth->reset_token($acct);
        say "Token for " . $acct->getCol('username') . ": $token";
        $count++;
    }
    say "Migrated $count account(s).";
}

1;
