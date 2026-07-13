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
has store            => undef;
has _activity_type   => sub { die "_activity_type is abstract — set in subclass" };

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

# ── Persistence delegation ──────────────────────────────────────────
# All disk I/O for activities.json goes through the central Activities
# model. Concrete activity objects update the shared table hashref
# (via inherited Model::save) but delegate the actual file write.
# This keeps _saveTable under the control of a single owner for
# deferred-write batching during bot processing.

sub _saveTable ($self) {
    # In production, all Activity objects have a store set by the app
    # accessors, delegating persistence to MagicMountain::Model::Activity.
    # Tests may create bare Activity objects without a store — fall back
    # to the inherited Model behavior for backward compatibility.
    return $self->SUPER::_saveTable unless $self->store;
    return $self->store->_saveTable;
}

# ── Type-filtered access ────────────────────────────────────────────
# Each concrete activity accessor (prospecting, market, black_market)
# must only return rows matching its own _activity_type discriminator.

sub get ($self, $id) {
    my $instance = $self->SUPER::get($id) or return;
    $instance->transitions($self->transitions);
    $instance->app($self->app);
    $instance->content_data($self->content_data);
    $instance->store($self->store);
    return $instance;
}

sub find ($self, $codeRef) {
    my $type = $self->_activity_type;
    return $self->SUPER::find(sub {
        return 0 unless $_[0]->{type} eq $type;
        $codeRef->(@_);
    });
}

sub create ($self, %params) {
    my $instance = $self->SUPER::create(%params);
    $instance->transitions($self->transitions);
    $instance->app($self->app);
    $instance->content_data($self->content_data);
    $instance->store($self->store);
    return $instance;
}

1;
