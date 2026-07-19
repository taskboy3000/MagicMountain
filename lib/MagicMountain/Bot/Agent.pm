package MagicMountain::Bot::Agent;
use Mojo::Base -base, -signatures;

has base_url   => 'http://127.0.0.1:9000';
has ua         => sub { Mojo::UserAgent->new };
has csrf_token => undef;
has svc_token  => undef;

sub login ($self, $name) {
    my $body = { displayName => $name };
    my $tx = $self->_req(POST => '/sessions', $body);
    my $json = $tx->res->json;
    die "Login failed: " . ($json->{error} // 'unknown') unless $json && $json->{ok};
    $self->csrf_token($json->{csrf_token});
    return $json;
}

sub logout ($self) {
    $self->_req(DELETE => '/sessions');
}

sub req ($self, $method, $path, $body = undef) {
    my $tx = $self->_req($method, $path, $body);
    my $json = $tx->res->json;
    die "$method $path failed: " . ($json->{error} // $tx->res->code // 'unknown')
        unless $json && (ref $json eq 'HASH') && $json->{ok};
    return $json;
}

sub _req ($self, $method, $path, $body = undef) {
    my $base = $self->base_url;
    $base =~ s|/$||;
    my $url = $base . $path;
    my $tx = $self->ua->build_tx($method => $url);
    $tx->req->headers->accept('application/json');
    if (defined $body) {
        $tx->req->headers->content_type('application/json');
        $tx->req->body(encode_json($body));
    }
    my $csrf = $self->csrf_token;
    $tx->req->headers->header('X-CSRF-Token' => $csrf) if $csrf;
    my $svc = $self->svc_token;
    $tx->req->headers->header('X-Bot-Service-Token' => $svc) if $svc;
    $tx = $self->ua->start($tx);
    return $tx;
}

# Read endpoints
sub nav       ($self) { $self->req(GET => '/nav') }
sub game      ($self) { $self->req(GET => '/game') }
sub prospect  ($self) { $self->req(GET => '/prospecting') }
sub market    ($self) { $self->req(GET => '/market') }
sub shed      ($self) { $self->req(GET => '/shed') }
sub skills    ($self) { $self->req(GET => '/skills') }
sub rivals    ($self) { $self->req(GET => '/pvp') }
sub factions  ($self) { $self->req(GET => '/factions') }
sub result    ($self) { $self->req(GET => '/result') }
sub black_mkt ($self) { $self->req(GET => '/black_market') }

# Write endpoints
sub begin_prospect   ($self)              { $self->req(POST => '/prospecting/begin') }
sub push             ($self)              { $self->req(POST => '/prospecting/push') }
sub stop             ($self)              { $self->req(POST => '/prospecting/stop') }
sub resolve_event    ($self, $choice_id)  { $self->req(POST => '/prospecting/resolve_event', { choice_id => $choice_id }) }
sub continue         ($self)              { $self->req(POST => '/result/continue') }
sub begin_market     ($self)              { $self->req(POST => '/market/begin') }
sub offer            ($self, $shed_item_id) { $self->req(POST => '/market/offer', { shed_item_id => $shed_item_id }) }
sub send_away        ($self)              { $self->req(POST => '/market/send_away') }
sub accept_counter   ($self)              { $self->req(POST => '/market/accept_counter') }
sub accept_bm        ($self)              { $self->req(POST => '/black_market/accept') }
sub withdraw_bm      ($self)              { $self->req(POST => '/black_market/withdraw') }
sub purchase_skill   ($self, $skill_id)   { $self->req(POST => '/skills/purchase', { skill_id => $skill_id }) }
sub apply_pressure   ($self, %params)     { $self->req(POST => '/pvp/apply', \%params) }

use constant GET  => 'GET';
use constant POST => 'POST';
use constant DELETE => 'DELETE';

use Mojo::JSON qw(encode_json);

1;
