package TestAuth;
use Modern::Perl;
use Crypt::Bcrypt qw(bcrypt bcrypt_check);

sub known_token { 'test-token' }

sub known_hash {
    state $hash = bcrypt('test-token', '2b', 10, 'test-salt-16-byt');
    return $hash;
}

sub setup_account {
    my ($class, $account_model, $name) = @_;
    my $acct = $account_model->create(username => $name);
    $acct->setCol('token_hash', $class->known_hash);
    $acct->save;
    return $acct;
}

sub login_body {
    my ($class, $name) = @_;
    return { displayName => $name, token => $class->known_token };
}

1;
