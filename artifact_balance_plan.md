# Artifact Pool Balance — Implementation Plan

## Overview

Two complementary checks to ensure the artifact pool remains balanced as new
artifacts are added, preventing faction coverage gaps that break loyalist
viability.

Both scripts live in `bin/`. The Makefile will have convenience targets.
AGENTS.md will document usage.

---

## Option A: Static Coverage Check (`bin/check_coverage`)

### Purpose

Fast, deterministic validation that every faction interest tag has sufficient
artifact coverage. Runs in <1s, suitable for running during content editing.

### Inputs

- `content/prospecting.yml` — **bare YAML array** (no top-level key).
  `YAML::XS::LoadFile` returns an arrayref directly.
- `content/factions.yml` — **hash with `factions:` key**.
  `YAML::XS::LoadFile` returns a hashref; access `->{factions}` for the list.

### Logic

1. Load artifacts from `prospecting.yml`, build `tag → [artifact_ids]` map
2. Load factions from `factions.yml`, extract each faction's `interests` list
3. For each faction, for each interest tag:
   - If tag has 0 artifacts → **ERROR** (unusable loyalist)
   - If tag has 1 artifact → **WARNING** (fragile, single point of failure)
   - If total weight of tag's artifacts < 10 → **WARNING** (too rare to
     consistently draw)
4. Print coverage matrix with full tag names
5. Print multi-artifact coverage index (which tags are covered by >1 artifact)
6. Exit code: 0 if clean, 1 if any tag has 0 artifacts, 2 if any warnings

### Output

```
=== Artifact Coverage Matrix ===
                    thermal  storage  food_processing  power  water  sanitation  medical_response  signal  revelation  force  instability  transformation
syndicate               1       2           1            1      0        0              0            0        0         0         0              0
libremount              1       0           0            1      2        1              2            0        0         0         0              0
faculty                 0       0           0            0      0        0              1            2        1         0         0              0
purifiers               0       0           0            0      0        0              1            0        0         1         2              0
revelationists          0       0           0            0      0        0              0            1        1         0         0              2

=== Multi-Artifact Tags (healthy) ===
  storage (2): cold_storage_001, memory_fabric_001
  water (2): aqueous_receiver_001, sanitation_coil_001
  signal (2): crystal_chime_001, biotelemeter_001
  field (2): void_core_001, crystal_chime_001
  instability (2): void_core_001, force_resonator_001
  transformation (2): revelation_lens_001, memory_fabric_001
  medical_response (2): aqueous_receiver_001, biotelemeter_001

=== Single-Artifact Tags (fragile — WARNING) ===
  thermal: thermal_box_001
  food_processing: cold_storage_001
  power: thermal_box_001
  sanitation: sanitation_coil_001
  revelation: revelation_lens_001
  force: force_resonator_001

=== Zero-Artifact Tags (ERROR) ===
  (none)
```

### Thresholds

| Metric | Threshold | Action |
|--------|-----------|--------|
| Tags with 0 artifacts | 0 | ERROR (exit 1) |
| Tags with 1 artifact | < 2 per tag | WARNING |
| Cumulative tag weight | < 10 total | WARNING |

---

## Option C: Loyalist Simulation Check (`bin/check_loyalist_balance`)

### Purpose

Runtime validation that each faction can support a viable loyalist strategy.
Accounts for artifact weight (draw frequency), value distribution, and market
interaction — things static coverage can't measure.

### Inputs

- `content/prospecting.yml`
- `content/factions.yml`

### Logic

### CLI Options

All simulation parameters are overridable at runtime:

| Option | Default | Description |
|--------|---------|-------------|
| `--count N` | 5 | Bots per faction sim |
| `--days N` | 7 | Days per faction sim |
| `--seed N` | 42 | RNG seed (omitting gives random) |
| `--push NAME` | greed | Push policy: greed, stage_guard, fixed, value, instability |
| `--threshold F` | 1.0 | Z-score below which a faction is flagged |

Defaults run ~15s total. Use higher --count/--days for stable results.

### Per-Faction Logic

For each faction in `content/factions.yml`:

1. Generate a temporary bot profile YAML with one profile:
   ```yaml
   - id: <push>_loyalist_<faction_id>
     push_policy: { name: "<push>", params: { ... } }
     sell_policy: { name: "faction_loyalist", params: { faction: "<faction_id>" } }
     skill_profile: { prospecting: 0, upcycling: 0, selling: 0 }
   ```
   Default push policy is `greed` (best-performing loyalist pairing from
   Experiment 12 at 170 avg). The goal is to test *faction coverage*, not
   push × faction interaction.

2. Run simulation via subprocess with the given --count/--days/--seed
   Same seed across factions removes RNG as a confound.

3. Parse transcript JSONL for sale events (score + count) and offer events
   (match rate), average across bots.

4. Clean up temp files. If a sim fails, skip and report.

### Output

```
=== Faction Loyalist Balance Check ===
Faction           | Avg Score | Avg Sales | Match% | vs Mean
------------------|-----------|-----------|--------|--------
syndicate         |   175     |   8.2     |  25%   | +1.02σ
revelationists    |   155     |   7.5     |  22%   | +0.58σ
libremount        |   142     |   6.8     |  20%   | +0.31σ
faculty           |    98     |   5.0     |  18%   | -0.45σ
purifiers         |    65     |   3.5     |  12%   | -0.97σ ⚠

Cross-faction mean: 127.0  σ: 44.5
Flagged: purifiers (65) — underperforms 1σ below mean.
  Interest tags: force, instability, medical_response
  Single-artifact tags: force (only force_resonator_001)
```

---

## Verification

After implementing each script:

1. **Option A**: Run `perl -Ilib bin/check_coverage` and verify:
   - Output matrix matches expected coverage from known artifact/faction data
   - Exit code 0 (no errors with current 10-artifact pool)
   - Temporarily remove an artifact YAML entry, re-run → exit code > 0

2. **Option C**: Run `perl -Ilib bin/check_loyalist_balance` and verify:
   - All 5 factions complete without errors
   - Output table has plausible scores (informed by Experiment 12 data)
   - Cross-faction mean is documented for future regression detection

3. **Makefile targets**: `make check-coverage` and `make check-loyalist`
   produce the same output as direct invocation.

---

## Integration

### Makefile targets

```makefile
check-coverage:
	perl -Ilib bin/check_coverage

check-loyalist:
	perl -Ilib bin/check_loyalist_balance
```

Override example:
```bash
make check-loyalist  # default: 5 bots, 7 days, greed, ~15s
perl -Ilib bin/check_loyalist_balance --count 10 --days 14  # ~60s, more stable
```

### AGENTS.md update

Add under Key Conventions or a new "Balance Checks" section:

> **Balance checks**: Run `make check-coverage` for fast validation that all
> faction interest tags have adequate artifact coverage. Run
> `make check-loyalist` (takes ~15s) to verify each faction can support a
> viable loyalist strategy via simulation. Add these to your workflow when
> modifying `content/prospecting.yml` or `content/factions.yml`.

---

## Implementation Order

1. `bin/check_coverage` — static check (simpler, no dependencies)
2. Update Makefile with `check-coverage` target
3. `bin/check_loyalist_balance` — sim-based check (depends on sim command)
4. Update Makefile with `check-loyalist` target
5. Update AGENTS.md with balance check documentation
6. Verify both scripts produce expected output

---

## Assumptions

- `greed` push policy will remain a viable loyalist pairing. If greed is
  rebalanced, Option C's push choice must be revisited.
- Same seed (42) across all factions is correct — it isolates faction
  coverage as the measured variable rather than RNG noise.
- Both scripts go in `bin/` (not `script/`), following the recent
  convention of keeping Mojo-agnostic helpers in `bin/`.
