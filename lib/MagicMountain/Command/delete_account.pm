package MagicMountain::Command::delete_account;
use Mojo::Base 'Mojolicious::Command', '-signatures';

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

    unless ($force) {
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
    # Sessions
    $self->app->session_store->delete_by_player_id($player_id);

    # Characters and their shed items
    my $chars = $self->app->characters;
    my $existing = $chars->find({ account_id => qr/^\Q$player_id\E$/ });
    for my $char (@$existing) {
        my $char_id = $char->getCol('id');
        $self->app->shed->load;
        for my $sid (keys %{ $self->app->shed->table }) {
            next unless $self->app->shed->table->{$sid}{char_id} && $self->app->shed->table->{$sid}{char_id} eq $char_id;
            $self->app->shed->delete($sid);
        }
        $chars->delete($char_id);
    }

    # Dispositions (permanent sale records)
    $self->app->disposition->load;
    my $disps = $self->app->disposition->find(sub { $_[0]->{player_id} eq $player_id });
    for my $d (@$disps) {
        $self->app->disposition->delete($d->getCol('disposition_id'));
    }

    # Season records (post-season archives)
    $self->app->season_records->load;
    my $recs = $self->app->season_records->find(sub { $_[0]->{player_id} eq $player_id });
    for my $r (@$recs) {
        $self->app->season_records->delete($r->getCol('record_id'));
    }

    $self->app->accounts->delete($player_id);

    $self->app->audit_log->log('account_deleted',
        player_id   => $player_id,
        player_name => $name,
    );
}

1;
