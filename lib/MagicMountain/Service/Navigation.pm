package MagicMountain::Service::Navigation;
use Mojo::Base '-base', '-signatures';

has app => sub { die "app is required" };

my %BASE_TAB = (
    idle => {
        home     => { active => 1, reason => undef },
        prospect => { active => 1, reason => undef },
        bazaar   => { active => 1, reason => undef },
        factions => { active => 1, reason => undef },
        skills   => { active => 1, reason => undef },
    },
    prospecting => {
        home     => { active => 1, reason => undef },
        prospect => { active => 1, reason => undef },
        bazaar   => { active => 0, reason => 'Finish your current expedition first' },
        factions => { active => 1, reason => undef },
        skills   => { active => 1, reason => undef },
    },
    market => {
        home     => { active => 1, reason => undef },
        prospect => { active => 0, reason => 'Complete your market visit first' },
        bazaar   => { active => 1, reason => undef },
        factions => { active => 1, reason => undef },
        skills   => { active => 1, reason => undef },
    },
);

my %TAB_ID_FOR = (
    home        => 'home',
    idle        => 'prospect',
    result      => 'home',
    prospecting => 'prospect',
    market      => 'bazaar',
    factions    => 'factions',
    skills      => 'skills',
    account     => 'account',
);

sub build_tabs ($self, $char, $type, $ap, $shed_count) {
    my $base     = $BASE_TAB{$type // 'idle'} // $BASE_TAB{idle};
    my @tab_ids  = qw(home prospect bazaar factions skills);
    my @tabs;
    for my $id (@tab_ids) {
        my $entry = { %{ $base->{$id} } };
        if ($id eq 'bazaar' && $entry->{active}) {
            if ($ap < 1) {
                $entry->{active} = 0; $entry->{reason} = 'No AP remaining';
            } elsif ($shed_count < 1) {
                $entry->{active} = 0; $entry->{reason} = 'No artifacts in shed';
            }
        }
        if ($id eq 'prospect' && $entry->{active}) {
            if ($ap < 2) {
                $entry->{active} = 0; $entry->{reason} = 'Not enough AP (2 required)';
            }
        }
        push @tabs, {
            id     => $id,
            active => $entry->{active},
            reason => $entry->{reason},
        };
    }
    return \@tabs;
}

sub secondary_tabs ($self, $char) {
    my $muted = $char->getCol('settings_muted') // 0;
    return [
        {
            id     => 'account',
            type   => 'nav',
            active => 1,
            label  => 'ACCOUNT',
            fragment_url => '/account?_format=fragment',
            target => 'secondary-content',
        },
        {
            id      => 'orientation',
            type    => 'action',
            active  => 1,
            label_live => '?',
            label   => '?',
            fragment_url => '/orientation?_format=fragment',
            target  => 'primary-content',
        },
        {
            id            => 'mute',
            type          => 'toggle',
            active        => 1,
            toggle_state  => $muted,
            key           => 'mute',
            label_live    => $muted ? '[)]' : ')))]',
            label         => $muted ? '[)]' : ')))]',
            labels        => { on => '[)]', off => ')))]' },
            action_url    => '/nav/toggle',
            method        => 'POST',
        },
    ];
}

sub tab_id_for ($self, $view) {
    return $TAB_ID_FOR{$view} || 'home';
}

sub resolve_view ($self, $stored_view, $active_type, $tabs) {
    my $view = $stored_view || $active_type || 'home';

    if (($view eq 'prospecting' || $view eq 'market') && !$active_type) {
        $view = 'home';
    }
    if ($active_type && $view ne $active_type) {
        $view = $active_type;
    }
    if (!$active_type) {
        my $tab_id = $self->tab_id_for($view);
        my ($tab) = grep { $_->{id} eq $tab_id } @$tabs;
        $view = 'home' unless $tab && $tab->{active};
    }
    return $view;
}

1;
