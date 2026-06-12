package MagicMountain::Command::list_accounts;
use Mojo::Base 'Mojolicious::Command', '-signatures';

has description => 'List all player accounts';
has usage       => "Usage: $0 list-accounts\n";

sub run ($self, @args) {
    my $accounts  = $self->app->accounts->all;
    my $sessions  = $self->app->session_store->all;
    my $timeout   = $self->app->config->{session_timeout_minutes} // 60;

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

    my @keys = keys %$accounts;
    if (!@keys) {
        say "No accounts found.";
        return;
    }

    say sprintf "%-40s %-20s %-10s %s", "ID", "Username", "Status", "Last Seen";
    say "-" x 100;
    for my $id (sort keys %$accounts) {
        my $row    = $accounts->{$id};
        my $status = $active_for{$id} ? 'online' : 'offline';
        my $last   = $active_for{$id} // ($row->{createdAt} ? scalar(localtime($row->{createdAt})) : 'unknown');
        say sprintf "%-40s %-20s %-10s %s", $id, $row->{username} // '', $status, $last;
    }
    say "";
    say scalar(@keys) . " account(s) total.";
}

1;
