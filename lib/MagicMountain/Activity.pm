package MagicMountain::Activity;
use Modern::Perl;
use Mojo::Base 'MagicMountain::Model', '-signatures';

use YAML::XS qw(LoadFile);

# ── Persisted columns ──────────────────────────────────────────────
# id, createdAt, updatedAt come from Model::defaultColumns
# char_id  — FK to characters table
# type     — discriminator (e.g. "prospecting")
# phase    — state-machine phase: idle | processing
# artifact — live artifact state (hashref, JSON-serialized by Model)
# customer — current customer state (hashref, JSON-serialized by Model)

has columns => sub ($self) {
    my $cols = $self->defaultColumns;
    return [ @$cols, qw(char_id type phase artifact customer pending_event) ];
};

# ── Ephemeral attributes (NOT persisted) ───────────────────────────
# Infrastructure/config, identical for all instances of a given
# activity type on a given app instance.

has transitions      => sub { {} };
has app              => sub { die "app is required" };
has log              => sub ($self) { $self->app->log };

# Read-only content (set by app class, loaded once, shared across instances)
has content_filename => undef;   # full path to YAML file, set by app class
has content_data     => undef;   # parsed YAML data, identical for all instances

# ── Content loading ────────────────────────────────────────────────
# The app class sets content_filename and calls load_content.
# Subclasses interpret content_data in their own domain-specific way.
# Idempotent — returns immediately if already loaded.

sub load_content ($self) {
    return if $self->content_data;
    return unless $self->content_filename;
    $self->content_data(LoadFile($self->content_filename));
    $self->log->debug(sprintf("Loaded content from %s", $self->content_filename));
    return $self;
}

# ── Column accessors ───────────────────────────────────────────────
# Bridge between Mojo attribute syntax ($self->phase('value')) and
# column storage ($self->row->{phase}). Persistence via save() reads
# from row, so values flow through correctly.

sub phase {
    my $self = shift;
    return $self->setCol('phase', shift) if @_;
    return $self->getCol('phase') // 'idle';
}

sub artifact {
    my $self = shift;
    return $self->setCol('artifact', shift) if @_;
    return $self->getCol('artifact');
}

sub customer {
    my $self = shift;
    return $self->setCol('customer', shift) if @_;
    return $self->getCol('customer');
}

# ── State-machine dispatch ─────────────────────────────────────────

sub _log_event ($self, $char, $event) {
    $event->{char_id} = $char->getCol('id');
    $event->{action_points} = $char->getCol('action_points');
    $self->app->transcript->log_event($event);
}

sub begin_activity ($self, $char, %params) {
    my $id = $char->getCol('pending_activity_id');
    my $activity = $id ? $self->get($id) : $self->create(char_id => $char->getCol('id'));
    return $activity->dispatch($char, 'begin', %params);
}

sub dispatch ($self, $char, $action, %params) {
    my $phase = $self->phase;

    die sprintf("illegal transition: %s -> %s", $phase, $action)
        unless grep { $_ eq $action } @{ $self->transitions->{$phase} // [] };

    die "no handler for action: $action"
        unless $self->can($action);

    return $self->$action($char, %params);
}

# ── Construction ──────────────────────────────────────────────────
# Override Model::get and Model::create to propagate ephemeral
# attributes. Model's versions pass only file/log/table/row to new();
# Activity instances additionally need transitions, app, content_data.

sub get ($self, $id) {
    my $instance = $self->SUPER::get($id) or return;
    $instance->transitions($self->transitions);
    $instance->app($self->app);
    $instance->content_data($self->content_data);
    return $instance;
}

sub create ($self, %params) {
    my $instance = $self->SUPER::create(%params);
    $instance->transitions($self->transitions);
    $instance->app($self->app);
    $instance->content_data($self->content_data);
    return $instance;
}

1;
