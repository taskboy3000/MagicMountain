use Modern::Perl;
use Test::More;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

# ── Boundary: Activities and Transcript ────────────────────────────
# Activities must not call $self->app->transcript directly.
# They inherit _log_event() from MagicMountain::Activity for transcript writes.
# AGENTS.md: "Transcript writes only through _log_event"

my @activity_files = grep { -f } glob("$FindBin::Bin/../lib/MagicMountain/Activity/*.pm");
for my $file (@activity_files) {
    open my $fh, '<', $file or die "Cannot open $file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    (my $label = $file) =~ s|.*/lib/||;
    ok($content !~ /\$self->app->transcript/,
        "$label does not call \$self->app->transcript directly");
}

# ── Boundary: Controller row access ────────────────────────────────
# Controllers must not access ->row directly; they should use getCol/setCol.
# Exception: Controller/Game.pm reads $char_model->row for pending_activity_id.
# AGENTS.md: "No State internals reached by leaf objects"

my @controller_files = grep { -f } glob("$FindBin::Bin/../lib/MagicMountain/Controller/*.pm");
for my $file (@controller_files) {
    open my $fh, '<', $file or die "Cannot open $file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    (my $label = $file) =~ s|.*/lib/||;
    next if $label eq 'MagicMountain/Controller/Game.pm';  # known exception
    ok($content !~ /->row\b/,
        "$label does not access ->row directly");
}

# ── Boundary: Template model mutations ─────────────────────────────
# Templates are pure renderers. They must not call model mutation methods.
# AGENTS.md: "Templates — pure iterators"

my @template_files = grep { -f } glob("$FindBin::Bin/../templates/**/*.html.ep");
for my $file (@template_files) {
    open my $fh, '<', $file or die "Cannot open $file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    (my $label = $file) =~ s|.*/templates/||;
    ok($content !~ /->(save|delete|create|setCol|nullCol)\b/,
        "$label does not call model mutation methods");
}

done_testing;
