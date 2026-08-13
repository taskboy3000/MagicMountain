package MagicMountain::Controller;
use Mojo::Base 'Mojolicious::Controller', '-signatures';

# ── Injected model dependencies ──────────────────────────────────
has accounts         => sub { shift->app->accounts };
has session_store    => sub { shift->app->session_store };
has characters       => sub { shift->app->characters };
has shed             => sub { shift->app->shed };
has seasons          => sub { shift->app->seasons };
has prospecting      => sub { shift->app->prospecting };
has market           => sub { shift->app->market };
has pawn             => sub { shift->app->pawn };
has activities       => sub { shift->app->activities };
has rate_limiter     => sub { shift->app->rate_limiter };
has faction_snapshots => sub { shift->app->faction_snapshots };
has season_records   => sub { shift->app->season_records };
has audit_log        => sub { shift->app->audit_log };
has pressures        => sub { shift->app->pressures };

# ── Injected service dependencies ───────────────────────────────
has auth_service     => sub { shift->app->auth_service };
has pvp_service      => sub { shift->app->pvp_service };
has dominance_service => sub { shift->app->dominance_service };
has pawn_calculator  => sub { shift->app->pawn_calculator };
has season_manager   => sub { shift->app->season_manager };
has skill_training   => sub { shift->app->skill_training };
has random_events    => sub { shift->app->random_events };
has character_view   => sub { shift->app->character_view };
has navigation       => sub { shift->app->navigation };
has suggestion       => sub { shift->app->suggestion };
has account_deletion => sub { shift->app->account_deletion };

sub active_season ($self) {
    $self->seasons->load;
    my $active = $self->seasons->find(sub { ($_[0]->{status} // '') eq 'active' });
    return @$active ? $active->[0] : undef;
}

sub _require_character ($self) {
    my $player_id = $self->current_player;
    return if !$player_id;
    my $season = $self->active_season;
    my $season_id = $season ? $season->getCol('id') : undef;

    $self->characters->load;
    my ($char) = @{ $self->characters->find(
        sub { $_[0]->{account_id} eq $player_id && (!$season_id || $_[0]->{season_id} eq $season_id) }
    ) };
    if (!$char) {
        $self->render(json => { ok => 0, error => 'No character' }, status => 404);
        return;
    }
    return $char;
}

sub _active_activity_type ($self, $char) {
    my $id = $char->getCol('pending_activity_id');
    return if !$id;
    # All activity types share activities.json, so loading any one model
    # populates the table for all. Load a known-good model to read the row.
    $self->prospecting->load;
    my $activity = $self->prospecting->get($id) or return;
    my $type     = $activity->getCol('type') or return;
    return 'prospecting' if $type eq 'prospecting';
    return 'market'      if $type eq 'market_visit';
    return 'pawn'        if $type eq 'pawn';
    return;
}

sub _render_action ($self, $result, $action_name) {
    $self->render(json => {
        %{ $result->{view} },
        csrf_token => $self->csrf_token,
    });
}

1;
