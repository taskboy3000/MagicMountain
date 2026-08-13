package MagicMountain::Controller::Admin;
use Mojo::Base 'MagicMountain::Controller', '-signatures';

sub reset_token ($self) {
    my $display_name = $self->req->json->{display_name} // '';
    return $self->render(json => { ok => 0, error => 'display_name required' }, status => 400) unless $display_name;

    my $account = $self->accounts->find_by_username($display_name);
    return $self->render(json => { ok => 0, error => 'Account not found' }, status => 404) unless $account;

    my $result = $self->auth_service->reset_token($account);
    $self->audit_log->log('token_reset_admin',
        player_name => $display_name,
    );

    $self->render(json => { ok => 1, token => $result->{token}, recovery_code => $result->{recovery_code} });
}

sub ban ($self) {
    my $display_name = $self->req->json->{display_name} // '';
    return $self->render(json => { ok => 0, error => 'display_name required' }, status => 400) unless $display_name;

    my $account = $self->accounts->find_by_username($display_name);
    return $self->render(json => { ok => 0, error => 'Account not found' }, status => 404) unless $account;

    $self->auth_service->ban($account);
    $self->audit_log->log('account_banned',
        player_name => $display_name,
    );

    $self->render(json => { ok => 1 });
}

sub unban ($self) {
    my $display_name = $self->req->json->{display_name} // '';
    return $self->render(json => { ok => 0, error => 'display_name required' }, status => 400) unless $display_name;

    my $account = $self->accounts->find_by_username($display_name);
    return $self->render(json => { ok => 0, error => 'Account not found' }, status => 404) unless $account;

    $self->auth_service->unban($account);
    $self->audit_log->log('account_unbanned',
        player_name => $display_name,
    );

    $self->render(json => { ok => 1 });
}

1;
