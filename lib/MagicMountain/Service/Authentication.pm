package MagicMountain::Service::Authentication;
# Security posture: tokens are 6-char (30 bits) from [A-Z2-9]. Weak
# offline but adequate: no PII, no payments, no privileged roles.
# Rate limiting (5/15min) prevents online brute-force. Bcrypt cost 10
# slows offline cracking. If this ever handles PII or real money,
# increase entropy to 128+ bits and use argon2id.

use Mojo::Base '-base', '-signatures';
use Crypt::Bcrypt qw(bcrypt bcrypt_check);

has app => sub { die "app is required" };

sub wordlist ($self) {
    state $words = do {
        my $file = $self->app->home . '/content/wordlist.txt';
        my @w;
        if (-e $file) {
            open my $fh, '<', $file or die "wordlist: $!";
            chomp(@w = <$fh>);
            close $fh;
        }
        @w ? \@w : [qw(alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega)];
    };
}

sub _random_int ($self, $max) {
    open my $fh, '<', '/dev/urandom' or die "/dev/urandom: $!";
    my $bytes;
    read $fh, $bytes, 4;
    close $fh;
    return unpack('L', $bytes) % $max;
}

my @TOKEN_CHARS = split '', 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

sub _token_char ($self) {
    return $TOKEN_CHARS[ $self->_random_int(scalar @TOKEN_CHARS) ];
}

sub _bcrypt_cost ($self) {
    return $self->app->config->{bcrypt_cost} // 10;
}

sub generate_token ($self) {
    return join '', map { $self->_token_char } 1 .. 6;
}

sub _salt ($self) {
    open my $fh, '<', '/dev/urandom' or die "/dev/urandom: $!";
    my $buf;
    read $fh, $buf, 16;
    close $fh;
    return $buf;
}

sub hash_token ($self, $token) {
    return bcrypt($token, '2b', $self->_bcrypt_cost, $self->_salt);
}

sub verify_token ($self, $token, $hash) {
    return 0 unless defined $hash && length $hash > 0;
    return bcrypt_check($token, $hash);
}

sub _random_hex ($self, $bytes) {
    open my $fh, '<', '/dev/urandom' or die "/dev/urandom: $!";
    my $buf;
    read $fh, $buf, $bytes;
    close $fh;
    return unpack('H*', $buf);
}

sub generate_remember_token ($self) {
    return $self->_random_hex(32);
}

sub generate_recovery_code ($self) {
    return join '', map { $self->_token_char } 1 .. 10;
}

sub new_account ($self, $display_name) {
    my $token = $self->generate_token;
    my $token_hash = $self->hash_token($token);
    my $recovery_code = $self->generate_recovery_code;
    my $recovery_hash = $self->hash_token($recovery_code);
    my $remember_token = $self->generate_remember_token;
    my $remember_hash = $self->hash_token($remember_token);

    my $account = $self->app->accounts->create(
        username            => $display_name,
        token_hash          => $token_hash,
        remember_token_hash => $remember_hash,
        recovery_code_hash  => $recovery_hash,
    );
    $account->save;
    return {
        account       => $account,
        token         => $token,
        recovery_code => $recovery_code,
        remember_token => $remember_token,
    };
}

sub login_or_create ($self, $display_name) {
    my $account = $self->app->accounts->find_by_username($display_name);
    return $self->new_account($display_name) unless $account;

    if ($account->getCol('banned')) {
        return { error => 'Account banned' };
    }

    my $token_hash = $account->getCol('token_hash');
    unless (defined $token_hash && length $token_hash > 0) {
        return { need_admin_reset => 1, display_name => $display_name };
    }

    return { need_token => 1, account => $account, display_name => $display_name };
}

sub verify_login ($self, $account, $token) {
    return { error => 'Account banned' } if $account->getCol('banned');

    my $token_hash = $account->getCol('token_hash');
    return { error => 'No token set' } unless $token_hash && length $token_hash > 0;

    return { error => 'Invalid token' } unless $self->verify_token($token, $token_hash);

    my $remember_token = $self->generate_remember_token;
    my $remember_hash = $self->hash_token($remember_token);
    $account->setCol('remember_token_hash', $remember_hash);
    $account->save;

    return { ok => 1, remember_token => $remember_token, account => $account };
}

sub verify_remember_token ($self, $account, $token) {
    my $hash = $account->getCol('remember_token_hash') // '';
    return 0 unless length $hash > 0;
    return bcrypt_check($token, $hash);
}

sub verify_recovery_code ($self, $account, $code) {
    my $hash = $account->getCol('recovery_code_hash') // '';
    return 0 unless length $hash > 0;
    return bcrypt_check($code, $hash);
}

sub recover_account ($self, $account) {
    my $token = $self->generate_token;
    my $token_hash = $self->hash_token($token);
    my $recovery_code = $self->generate_recovery_code;
    my $recovery_hash = $self->hash_token($recovery_code);
    my $remember_token = $self->generate_remember_token;
    my $remember_hash = $self->hash_token($remember_token);

    $account->setCol('token_hash', $token_hash);
    $account->setCol('recovery_code_hash', $recovery_hash);
    $account->setCol('remember_token_hash', $remember_hash);
    $account->save;

    $self->app->session_store->delete_by_player_id($account->getCol('id'));

    return {
        account        => $account,
        token          => $token,
        recovery_code  => $recovery_code,
        remember_token => $remember_token,
    };
}

sub admin_authenticate ($self, $secret) {
    my $expected = $self->app->config->{admin_secret} // 'override-me';
    return 0 if $expected eq 'override-me' || $expected eq 'surewhynot';
    return $secret eq $expected;
}

sub reset_token ($self, $account) {
    my $token = $self->generate_token;
    my $token_hash = $self->hash_token($token);
    my $recovery_code = $self->generate_recovery_code;
    my $recovery_hash = $self->hash_token($recovery_code);

    $account->setCol('token_hash', $token_hash);
    $account->setCol('remember_token_hash', '');
    $account->setCol('recovery_code_hash', $recovery_hash);
    $account->save;

    $self->app->session_store->delete_by_player_id($account->getCol('id'));

    return { token => $token, recovery_code => $recovery_code };
}

sub ban ($self, $account) {
    $account->setCol('banned', 1);
    $account->save;
    $self->app->session_store->delete_by_player_id($account->getCol('id'));
}

sub unban ($self, $account) {
    $account->setCol('banned', 0);
    $account->save;
}

1;
