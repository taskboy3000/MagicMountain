# Architecture Drift Report

**Date**: 2026-08-13
**Scope**: Full codebase audit against AGENTS.md layer boundaries

---

## Methodology

Every `.pm` file under `lib/MagicMountain/Controller/`, `lib/MagicMountain/Model/`, `lib/MagicMountain/Service/`, `lib/MagicMountain/Activity/`, and every `.html.ep` file under `templates/` was examined against the architectural constraints defined in `AGENTS.md` and `.opencode/rules/`.

Violations are categorized by layer, with file:line references and code context.

---

## 1. Controller Violations

Controllers MUST NOT implement game rules, calculate derived state, build recommendations, assemble narrative, determine navigation policy, or mutate domain objects except through model/service APIs. Controllers SHOULD ONLY extract HTTP params, dispatch to services/activities, stash, render.

### 1.1 Direct Model Row Access — `Game.pm`

**File**: `lib/MagicMountain/Controller/Game.pm`
**Severity**: High

```perl
# Line 32
my $row = $char_model->row;

# Line 39
my $id = $row->{pending_activity_id};

# Lines 103-106
score             => $row->{score} // 0,
scrap             => $row->{scrap} // 0,
action_points     => $row->{action_points} // 0,
action_points_max => $row->{action_points_max} // 15,
```

Bypasses `getCol` accessors and column validation entirely. Should use `$char_model->getCol('score')`, etc.

### 1.2 Domain Mutations in Controller — `Nav.pm`

**File**: `lib/MagicMountain/Controller/Nav.pm`
**Severity**: High

```perl
# Lines 111-112 — Controller persists view selection
$char->setCol('current_view', $view);
$char->save;

# Lines 133-134 — Controller toggles mute state
$char->setCol('settings_muted', $current ? 0 : 1);
$char->save;
```

View selection and mute toggle are domain mutations that belong in services.

### 1.3 Navigation Policy in Controller — `Nav.pm`

**File**: `lib/MagicMountain/Controller/Nav.pm`
**Severity**: High

```perl
# Lines 58-75 — Controller decides tab availability based on game rules
if ($base->{bazaar}{active}) {
    if ($ap < 1) {
        $overrides->{bazaar} = { active => 0, reason => 'No AP remaining' };
    } elsif ($shed_count < 1) {
        $overrides->{bazaar} = { active => 0, reason => 'No artifacts in shed' };
    }
}
if ($base->{prospect}{active}) {
    if ($ap < 2) {
        $overrides->{prospect} = { active => 0, reason => 'Not enough AP (2 required)' };
    }
}
if ($base->{pawn}{active}) {
    my $calc = $self->pawn_calculator;
    if (!$calc->has_banned_items($char)) {
        $overrides->{pawn} = { active => 0, reason => 'No restricted items' };
    }
}
```

AP costs and item requirements are game rules. The Navigation service already has `base_tab_state` and `build_tabs` — these overrides should be computed there.

### 1.4 Narrative Assembly in Controller — `Nav.pm`

**File**: `lib/MagicMountain/Controller/Nav.pm`
**Severity**: High

```perl
# Lines 155-209 (_context_text method) — Controller builds descriptive narrative
return sprintf "INSTABILITY %d/%d  \x{7c}  STAGE %s  \x{7c}  VALUE %d",
    $a->{instability} // 0, $a->{max_instability} // 0,
    uc($a->{stage} // ''), $a->{value} // 0;

return sprintf "BUYER: %s  \x{7c}  IRRITATION %d  \x{7c}  MOOD: %s",
    $short, $c->{irritation} // 0, $state;

return sprintf "BROKER  \x{7c}  %s  \x{7c}  SEIZURE RISK %.0f%%",
    $c->{outcome} ? 'RESULT' : 'AWAITING', $seizure_pct;
```

Lines 182-186 also compute derived state: `my $seizure_pct = $c->{outcome} ? 0 : ($c->{seizure_chance} // 0) * 100;`

All narrative assembly and derived display values belong in a service.

### 1.5 Domain Mutations in Controller — `Result.pm`

**File**: `lib/MagicMountain/Controller/Result.pm`
**Severity**: High

```perl
# Lines 41-43 (dismiss action)
$char->nullCol('result');
$char->setCol('current_view', 'home');
$char->save;

# Lines 56-66 (continue action) — Controller determines navigation AND mutates state
$char->nullCol('result');
if ($activity_type eq 'prospecting') {
    $self->prospecting->begin_activity($char);
    $char->setCol('current_view', 'prospecting');
} else {
    $self->market->begin_activity($char);
    $char->setCol('current_view', 'market');
}
```

Navigation determination and view mutation belong in a service.

### 1.6 Domain Mutation in Controller — `Market.pm`

**File**: `lib/MagicMountain/Controller/Market.pm`
**Severity**: Medium

```perl
# Lines 32-35 — Controller clears domain state directly
$c->{last_sale} = undef;
$c->{last_message} = undef;
$activity->customer($c);
$activity->save;
```

### 1.7 Derived State in Controller — `Market.pm`

**File**: `lib/MagicMountain/Controller/Market.pm`
**Severity**: Medium

```perl
# Lines 41-43 — Mood threshold logic (game rule)
my $mood = ($c->{irritation} // 0) <= 1 ? 'happy'
         : ($c->{irritation} // 0) <= 3 ? 'neutral'
         : 'mad';

# Lines 54-57 — Skill-gated feature exposure (game rule)
($sell >= 3 ? (
    budget_min => $c->{soft_budget},
    budget_max => $c->{absolute_budget},
) : ()),
```

### 1.8 Game Rules in Controller — `Skills.pm`

**File**: `lib/MagicMountain/Controller/Skills.pm`
**Severity**: Medium

```perl
# Lines 4-25 (_build_skill_actions) — Level thresholds, cost lookup, affordability
my $cur = $s->{current_level} // 0;
my $max = $s->{max_level} // 3;
my $at_max = $cur >= $max;
my $next_cost = $at_max ? undef : ($s->{levels}[$cur]{cost} // undef);
next unless !$at_max && defined $next_cost;
...
($scrap < $next_cost ? (disabled => undef) : ()),
```

### 1.9 Derived State in Controller — `Home.pm`

**File**: `lib/MagicMountain/Controller/Home.pm`
**Severity**: Medium

```perl
# Line 42 — Fresh player detection
my $fresh_player = !$type && !$shed_count && !$char->getCol('scrap');

# Lines 47-51 — Top-selling faction computation
if (my $top_id = (sort { ($sales->{$b} // 0) <=> ($sales->{$a} // 0) } keys %$sales)[0]) {
    $top_sales_line = sprintf('%s ★★★★★', $label);
}
```

### 1.10 Ranking Computation in Controller — `Leaderboard.pm`

**File**: `lib/MagicMountain/Controller/Leaderboard.pm`
**Severity**: Medium

```perl
# Lines 14-24 — Ranking is derived state
my @sorted = sort { $b->getCol('score') <=> $a->getCol('score') } @$chars;
for my $i (0 .. $#sorted) {
    push @ranked, { rank => $i + 1, ... };
}
```

### 1.11 Domain Mutation in Controller — `OnboardingNotice.pm`

**File**: `lib/MagicMountain/Controller/OnboardingNotice.pm`
**Severity**: Medium

```perl
# Lines 60-61 — Bitwise manipulation of game state
$char->setCol('pending_notices', $pending & ~$bit);
$char->save;
```

### 1.12 Navigation Policy in Controller — `Idle.pm`

**File**: `lib/MagicMountain/Controller/Idle.pm`
**Severity**: Medium

```perl
# Lines 15-16 — AP cost checks (game rules)
can_prospect => $ap >= 2,
can_market   => $ap >= 1 && $shed_count > 0,
```

### 1.13 Domain Mutation in Controller — `Orientation.pm`

**File**: `lib/MagicMountain/Controller/Orientation.pm`
**Severity**: Low

```perl
# Lines 20-21
$char_model->setCol('seen_orientation', 1);
$char_model->save;
```

### 1.14 Domain Object Creation in Controller — `Pawn.pm`

**File**: `lib/MagicMountain/Controller/Pawn.pm`
**Severity**: Medium

```perl
# Line 75 — Creates activity directly in controller
$activity //= $pawn->create(char_id => $char->getCol('id'));
```

---

## 2. Model Violations

Models MUST use `getCol`/`setCol` accessors. MUST NOT access `$self->{row}` directly outside the model class. MUST NOT use `_saveTable` (private). MUST NOT access `$model->table->{$id}` directly.

### 2.1 Banned `_saveTable` Usage — `Pressure.pm`

**File**: `lib/MagicMountain/Model/Pressure.pm`
**Severity**: High

```perl
# Lines 32, 50, 52-53
my @matches = grep {
    $_->{$age_key}              eq $char_id
    && ($faction_allowed       || $_->{faction_id} eq $faction_id)
    && !$_->{ $self->_consumed_col($age_key) }
    && ($_->{createdAt} // 0)  >= $cutoff
} values %{$self->table};           # Raw table access

# ...
delete $self->table->{$_->{id}} for @purge;  # Raw table mutation
$self->_saveTable;                            # BANNED private method
```

The code includes a comment acknowledging the violation: `# ok: model violation for performance`. Should use `$model->save_table` and `$model->delete`.

### 2.2 Accessor Bypass in validate_save — `Character.pm`

**File**: `lib/MagicMountain/Model/Character.pm`
**Severity**: Medium

```perl
# Lines 50-58
sub validate_save ($self) {
    my $ap = $self->row->{action_points};           # Direct row access
    my $max = $self->row->{action_points_max} // 15;
    die "invariant: scrap < 0" if defined $self->row->{scrap} && $self->row->{scrap} < 0;
    die "invariant: score < 0" if defined $self->row->{score} && $self->row->{score} < 0;
    for my $sk (qw(skill_prospecting skill_upcycling skill_selling skill_smuggling)) {
        my $v = $self->row->{$sk};
        die "invariant: $sk ($v) out of range 0-4" if defined $v && ($v < 0 || $v > 4);
    }
}
```

Inside the model class (so technically permitted), but bypasses the accessor abstraction layer that column declarations are designed to enforce.

---

## 3. Service Violations

Services MUST contain extracted game logic. MUST NOT call `url_for` or hardcode URL paths. MUST NOT access HTTP/IO loop infrastructure.

### 3.1 Hardcoded URL in Service — `RandomEvents.pm`

**File**: `lib/MagicMountain/Service/RandomEvents.pm`
**Severity**: High

```perl
# Line 338
push @resolved, {
    # ...
    attrs => {
        'data-action-url' => '/prospecting/resolve_event',  # Hardcoded path
        'data-method'     => 'POST',
        'data-choice-id'  => $choice->{id},
        class             => 'mm-btn mm-btn-primary',
    },
};
```

This hardcoded path will break behind a reverse-proxy sub-path deployment. The URL must be injected by the calling controller.

### 3.2 Hardcoded Fallback URLs in Service — `Navigation.pm`

**File**: `lib/MagicMountain/Service/Navigation.pm`
**Severity**: High

```perl
# Line 93
fragment_url => $urls->{factions_url} // '/factions?_format=fragment',

# Line 102
fragment_url => $urls->{account_url} // '/account?_format=fragment',

# Line 110
fragment_url => $urls->{orientation_url} // '/orientation?_format=fragment',

# Line 121
action_url    => $urls->{toggle_url} // '/nav/toggle',
```

Fallback hardcoded URL paths bypass `url_for` and break behind a reverse proxy. The controller must always supply these URLs; the service should not have fallback paths.

### 3.3 HTTP Infrastructure in Service — `DailyMaintenance.pm`

**File**: `lib/MagicMountain/Service/DailyMaintenance.pm`
**Severity**: Medium

```perl
# Lines 4-5
use Mojo::UserAgent;
use Mojo::IOLoop;

# Line 163
$deadline_timer = Mojo::IOLoop->timer($deadline_minutes * 60 => sub { ... });

# Line 170
$child = Mojo::IOLoop->subprocess(
    sub { exec @cmd; },
    sub ($subprocess, $exit_code) { ... },
);

# Lines 152-154 — Daemon URL construction from env/config
my $daemon_url = $ENV{MOUNTAIN_DAEMON_URL} // $app->config->{port} // 9000;
$daemon_url = "http://localhost:$daemon_url" if $daemon_url =~ /^\d+$/;
```

Subprocess management, event-loop timers, and daemon URL construction are infrastructure concerns that belong in a controller or command layer.

### 3.4 Direct Table Access in Service — `SeasonFinalizer.pm`

**File**: `lib/MagicMountain/Service/SeasonFinalizer.pm`
**Severity**: High

```perl
# Lines 32-39
for my $sid (keys %{ $app->shed->table }) {       # Raw table access
    my $row = $app->shed->table->{$sid};            # Raw table access
    next unless $row->{char_id};
    my $cref = $app->characters->table->{$row->{char_id}}; # Cross-model raw access
    next unless $cref && $cref->{season_id} eq $season_id;
    $clearance{ $row->{char_id} } += ($row->{decayed_value} // 0);
    delete $app->shed->table->{$sid};               # Raw table mutation
}
$app->shed->save;                                   # Bare save (no sync_row)
```

Bypasses `get`, `getCol`, `setCol`, `find`, and `delete` model methods entirely. Skips `validate_save` that would run during normal `save()`.

---

## 4. Activity Violations

Activity handlers MUST use `_log_event` for transcript writes — never `$self->app->transcript`.

### 4.1 Missing _log_event — `Pawn.pm`

**File**: `lib/MagicMountain/Activity/Pawn.pm`
**Severity**: Low

```perl
# Lines 186-203 (offer_next handler)
sub offer_next ($self, $char, %params) {
    $self->phase('idle');
    $self->customer(undef);
    $self->save;

    $char->setCol('result', undef);
    $char->setCol('current_view', 'pawn');
    $char->save;

    return { view => { ok => 1, result => 'offer_next', ... } };
}
```

Every other handler in all three activities (Prospecting, MarketVisit, Pawn) calls `_log_event` for every state transition. This handler is the sole exception — the state transition is not auditable.

---

## 5. Template Violations

Templates MUST iterate data structures blindly. MUST NOT contain game logic. MUST NOT access `$self->app` to reach models or services. MUST NOT contain inline `<script>` tags.

### 5.1 Game Logic in Template — `broker.html.ep`

**File**: `templates/pawn/broker.html.ep`
**Severity**: Medium

```erb
# Line 15 — Randomness in template
$self->app->pawn->content_data->{closed}[int(rand(scalar @{$self->app->pawn->content_data->{closed}}))]

# Line 30 — Direct service access
%   my $calc = $self->app->pawn_calculator;
%   my $ch = stash('char');
%   if ($calc->has_banned_items($ch)) {

# Line 43 — Randomness + model internals
% my $arrival = $self->app->pawn->content_data->{arrival}[int(rand(scalar @{$self->app->pawn->content_data->{arrival}}))];
```

Three violations in one file: `rand()` (non-deterministic game logic), `$self->app->pawn_calculator` (service access), and `$self->app->pawn->content_data` (model internals).

### 5.2 Affordability Computation in Template — `training.html.ep`

**File**: `templates/skills/training.html.ep`
**Severity**: Medium

```erb
# Line 17 — Affordability check
%   my $disabled = $scrap < $next_cost;
```

The template compares player scrap against skill upgrade cost. This belongs in the controller, which should stash a pre-computed `$disabled` flag.

### 5.3 Trait-Matching Logic in Template — `salvage_ledger.html.ep`

**File**: `templates/components/salvage_ledger.html.ep`
**Severity**: Medium

```erb
# Line 21 — Set intersection computation
%   my $has_match = $item->{behaviors} && grep { my $t = $_; grep { $t eq $_ } @$cpt } @{$item->{behaviors}};
```

Performs a set-intersection between item behaviors and climate premium traits. Domain logic that should be pre-computed by the controller or a service.

---

## 6. Summary Table

| # | Layer | File | Lines | Violation | Severity |
|---|-------|------|-------|-----------|----------|
| 1 | Controller | Game.pm | 32, 39, 103-106 | Direct `$row->{...}` access | High |
| 2 | Controller | Nav.pm | 111-112, 133-134 | Domain mutations (setCol + save) | High |
| 3 | Controller | Nav.pm | 58-75 | Navigation policy (AP/item rules) | High |
| 4 | Controller | Nav.pm | 155-209 | Narrative assembly + derived state | High |
| 5 | Controller | Result.pm | 41-43, 56-66 | Domain mutations + navigation policy | High |
| 6 | Controller | Market.pm | 32-35 | Domain mutation (clear state) | Medium |
| 7 | Controller | Market.pm | 41-43, 54-57 | Derived state (mood, skill gate) | Medium |
| 8 | Controller | Skills.pm | 4-25 | Game rules (level/cost/affordability) | Medium |
| 9 | Controller | Home.pm | 42, 47-51 | Derived state (fresh player, top faction) | Medium |
| 10 | Controller | Leaderboard.pm | 14-24 | Ranking computation | Medium |
| 11 | Controller | OnboardingNotice.pm | 60-61 | Domain mutation (bitwise) | Medium |
| 12 | Controller | Idle.pm | 15-16 | Navigation policy (AP costs) | Medium |
| 13 | Controller | Orientation.pm | 20-21 | Domain mutation | Low |
| 14 | Controller | Pawn.pm | 75 | Domain object creation | Medium |
| 15 | Model | Pressure.pm | 32, 50, 52-53 | Banned `_saveTable` + raw table mutation | High |
| 16 | Model | Character.pm | 50-58 | `$self->row->{...}` in validate_save | Medium |
| 17 | Service | RandomEvents.pm | 338 | Hardcoded URL path | High |
| 18 | Service | Navigation.pm | 93, 102, 110, 121 | Hardcoded fallback URLs | High |
| 19 | Service | DailyMaintenance.pm | 4-5, 152-170 | HTTP infrastructure (IOLoop, UA) | Medium |
| 20 | Service | SeasonFinalizer.pm | 32-39 | Direct table access/mutation | High |
| 21 | Activity | Pawn.pm | 186-203 | Missing _log_event | Low |
| 22 | Template | broker.html.ep | 15, 30, 43 | Game logic + service access + rand() | Medium |
| 23 | Template | training.html.ep | 17 | Affordability computation | Medium |
| 24 | Template | salvage_ledger.html.ep | 21 | Trait-matching logic | Medium |

---

## 7. Pattern Analysis

### Pressure Points

The drift concentrates in three areas:

1. **Nav.pm** — The single worst file. Navigation policy, narrative assembly, and domain mutations all live here despite the Navigation service existing. This is the primary candidate for extraction.

2. **Controller layer broadly** — Derived state computation (mood, ranking, affordability, fresh-player detection) is scattered across 6+ controllers. A `GameState` service or expanding the existing `CharacterView` service could absorb this.

3. **broker.html.ep** — The only template with significant violations. Randomness, service access, and model internals all in one file. The Pawn controller needs to pre-compute everything this template renders.

### What's Clean

- **Activity handlers** — Nearly perfect. Only one missing `_log_event` across all three activity types.
- **Template URL generation** — Zero hardcoded URL paths in templates. All use `url_for`.
- **No inline JS** — Zero inline `<script>` tags in any template.
- **Model layer** — Mostly clean. Only Pressure.pm and Character.pm show drift.

### Risk Assessment

This drift is **manageable but compounding**. Each individual violation is small ("it's just a sprintf"), but collectively they mean:
- Game rules are duplicated (AP costs in Nav.pm, Idle.pm, and the Navigation service)
- Templates make decisions that should be pre-computed
- The controller layer does work that should be in services

The bones are solid. The activity system, the model layer, and the template URL discipline are all well-maintained. The drift is concentrated in specific files that could be refactored without broad impact.
