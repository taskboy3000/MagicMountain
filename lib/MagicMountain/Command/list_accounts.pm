package MagicMountain::Command::list_accounts;
use Mojo::Base 'Mojolicious::Command', '-signatures';

has description => 'List player accounts, optionally filtered by season';
has usage       => "Usage: $0 list-accounts\n"
                 . "       $0 list-accounts --season active\n"
                 . "       $0 list-accounts --season \"Season 5\"\n";

sub run ($self, @args) {
    my $season_arg;
    while (@args) {
        my $arg = shift @args;
        if ($arg eq '--season' && @args) {
            $season_arg = shift @args;
        }
    }

    my $accounts = $self->app->accounts->all;
    my $sessions = $self->app->session_store->all;
    my $timeout  = $self->app->config->{session_timeout_minutes} // 60;

    my %active_for;
    for my $sid (keys %$sessions) {
        my $s = $sessions->{$sid};
        my $pid = $s->{player_id};
        next unless $pid;
        my $last = $s->{last_active} // 0;
        if ((time - $last) <= ($timeout * 60)) {
            $active_for{$pid} = scalar(localtime($last));
        }
    }

    my %account_has_score;

    if (defined $season_arg) {
        $self->app->seasons->load;
        my $season;
        if ($season_arg eq 'active') {
            ($season) = @{ $self->app->seasons->find(sub { ($_[0]->{status} // '') eq 'active' }) };
            die "No active season.\n" unless $season;
        } else {
            my $matches = $self->app->seasons->find(sub { ($_[0]->{label} // '') eq $season_arg });
            die "Season '$season_arg' not found.\n" unless @$matches;
            $season = $matches->[0];
        }

        my $season_id = $season->getCol('id');
        $self->app->characters->load;
        my $chars = $self->app->characters->find(sub { $_[0]->{season_id} eq $season_id });
        for my $char (@$chars) {
            my $aid = $char->getCol('account_id');
            $account_has_score{$aid} = $char->getCol('score') // 0;
        }
    }

    my @keys = sort keys %$accounts;
    if (defined $season_arg) {
        @keys = grep { exists $account_has_score{$_} } @keys;
    }

    if (!@keys) {
        say "No accounts found." . (defined $season_arg ? " for specified season." : "");
        return;
    }

    if (defined $season_arg) {
        say sprintf "%-40s %-20s %-10s %-8s %s", "ID", "Username", "Status", "Score", "Last Seen";
        say "-" x 108;
        for my $id (@keys) {
            my $row    = $accounts->{$id};
            my $status = $active_for{$id} ? 'online' : 'offline';
            my $last   = $active_for{$id} // ($row->{createdAt} ? scalar(localtime($row->{createdAt})) : 'unknown');
            say sprintf "%-40s %-20s %-10s %-8s %s", $id, $row->{username} // '', $status,
                $account_has_score{$id}, $last;
        }
    } else {
        say sprintf "%-40s %-20s %-10s %s", "ID", "Username", "Status", "Last Seen";
        say "-" x 100;
        for my $id (@keys) {
            my $row    = $accounts->{$id};
            my $status = $active_for{$id} ? 'online' : 'offline';
            my $last   = $active_for{$id} // ($row->{createdAt} ? scalar(localtime($row->{createdAt})) : 'unknown');
            say sprintf "%-40s %-20s %-10s %s", $id, $row->{username} // '', $status, $last;
        }
    }
    say "";
    say scalar(@keys) . " account(s)" . (defined $season_arg ? " in selected season." : " total.");
}

1;
