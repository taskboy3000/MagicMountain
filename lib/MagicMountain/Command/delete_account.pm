package MagicMountain::Command::delete_account;
use Mojo::Base 'Mojolicious::Command', '-signatures';

use MagicMountain::Service::AccountDeletion;

has description => 'Delete one or more player accounts and all associated data';
has usage       => "Usage: $0 delete-account --name <username>\n"
                 . "       $0 delete-account --prefix <prefix> [--force]\n";

sub run ($self, @args) {
    $| = 1;
    my ($name, $prefix, $force);
    while (@args) {
        my $arg = shift @args;
        if ($arg eq '--name' && @args) {
            $name = shift @args;
        } elsif ($arg eq '--prefix' && @args) {
            $prefix = shift @args;
        } elsif ($arg eq '--force') {
            $force = 1;
        }
    }

    if ($prefix) {
        $self->_delete_by_prefix($prefix, $force);
        return;
    }

    die "Usage: $0 delete-account --name <username>\n"
      . "       $0 delete-account --prefix <prefix> [--force]\n"
        unless $name;

    $self->_delete_one($name);
}

sub _delete_one ($self, $name) {
    my $account = $self->app->accounts->find_by_username($name);
    die "Account '$name' not found.\n" unless $account;

    my $player_id = $account->getCol('id');
    $self->_remove_account_data($player_id, $name);
    say "Account '$name' deleted.";
}

sub _delete_by_prefix ($self, $prefix, $force) {
    my $accounts = $self->app->accounts->find({ username => qr/^\Q$prefix\E/ });
    die "No accounts found with prefix '$prefix'.\n" unless @$accounts;

    if (!$force) {
        say "Found " . scalar(@$accounts) . " account(s) matching prefix '$prefix'.";
        print STDERR "Delete them all? [y/N] ";
        my $answer = <STDIN>;
        chomp $answer;
        die "Aborted.\n" unless lc($answer) eq 'y';
    }

    for my $account (@$accounts) {
        my $name      = $account->getCol('username');
        my $player_id = $account->getCol('id');
        $self->_remove_account_data($player_id, $name);
    }
    say "Deleted " . scalar(@$accounts) . " account(s) matching prefix '$prefix'.";
}

sub _remove_account_data ($self, $player_id, $name) {
    MagicMountain::Service::AccountDeletion->new(app => $self->app)->delete_account($player_id);
}

1;
