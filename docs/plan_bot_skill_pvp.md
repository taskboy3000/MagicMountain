# Plan: Bot Skill Purchasing and PvP Participation

## Context
- Stack: Perl (Mojolicious/Moo/Durance), Test2::V0
- Dependencies: None new
- Test: Test2::V0 with Main() subroutine structure
- Tooling: `make indent && make clean`, `prove t`, `perl -Ilib script/mountain simulate`
- Season defaults: 30 days, bots start with 15 AP

Current BotRunner::run_day flow: Prospecting -> Black Market -> Market -> PvP Pressure
SkillTraining::purchase does not log to transcript.
9 bot profiles in content/bots.yml, all with skill_profile: { all 0 } and no skill_policy or pvp_aggressiveness.
No $app->skill_training attribute exists (controllers instantiate SkillTraining inline).

## Steps

### Step 1: Add transcript logging to SkillTraining::purchase
**File**: lib/MagicMountain/Service/SkillTraining.pm
- After successful purchase, log skill_purchase event to transcript
- Fields: char_id, day (from $self->app->active_season->getCol('day')), skill (id), level (new level), cost, scrap_remaining
- Use $self->app->transcript->log_event({...})

**Verify**: perl -Ilib script/mountain report shows skill_purchase events after a purchase

### Step 2: Add skill_training attribute to MagicMountain.pm
**File**: lib/MagicMountain.pm
- Add: has skill_training => sub { MagicMountain::Service::SkillTraining->new(app => shift) };
- This gives BotRunner and controllers a consistent access point via $self->app->skill_training

### Step 3: Create Bot::SkillPolicy module
**File**: lib/MagicMountain/Bot/SkillPolicy.pm
- Follows the SellPolicy.pm functional dispatch-table pattern (not OO/PressurePolicy)
- Single entry point: sub decide($char, $policy_params, $skills_data, $app) returning:
  - A hashref { skill_id => "prospecting", level => 2, cost => 250 } for the next purchase
  - undef if nothing affordable

- Three policies:

| Policy | Behavior |
|---|---|
| immediate | Sort all unowned skill levels by cost ascending; buy cheapest affordable while keeping reserve |
| specialize | Pick first skill tree from priority list that is not maxed; buy next level in that tree; only switch trees when current tree is maxed |
| never | Never buy (current baseline) |

- Parameters: reserve (min scrap to keep after purchase, default 30), priority (ordered list of skill IDs for specialize)
- Reserve ensures scrap >= cost + reserve before buying
- Unknown policy name falls back to 'never'
- Missing skill_policy in profile defaults to { name => 'never' }

**Tests**: test_skill_policy_immediate, test_skill_policy_specialize, test_skill_policy_never, test_skill_policy_reserve, test_skill_policy_unknown_defaults_to_never, test_skill_policy_missing_defaults_to_never

**Verify**: prove t passes

### Step 4: Integrate skill buying into BotRunner::run_day
**File**: lib/MagicMountain/Service/BotRunner.pm
- Add skill-buying phase in run_day after market (both normal and BM paths converge) and before pressure phase
- Flow: Prospecting -> BM/Market -> Skill Buying -> PvP Pressure
- Use $self->app->skill_training for purchase execution
- Cap at 1 purchase per bot per day (prevents dumping all scrap in one day)
- Load profile's skill_policy, call MagicMountain::Bot::SkillPolicy::decide
- Execute purchase via $self->app->skill_training->purchase($char, $skill_id)
- Log single transcript event per day: policy_skill_purchase with profile_id, policy name, skill_id, level, cost
- (SkillTraining's own skill_purchase event logs the raw purchase; BotRunner's event adds policy context -- they are complementary, not duplicative)

**Pseudo code**:
```
my $policy_params  = $profile->{skill_policy} // { name => 'never' };
my $decision = MagicMountain::Bot::SkillPolicy::decide($char, $policy_params, $self->app->skills_data, $self->app);
if ($decision) {
    my $result = $self->app->skill_training->purchase($char, $decision->{skill_id});
    if ($result->{ok}) {
        log policy_skill_purchase event
    }
}
```

- Import MagicMountain::Bot::SkillPolicy at top

### Step 5: Update bot profiles
**File**: content/bots.yml
- Replace skill_profile with skill_policy per profile
- Add pvp_aggressiveness values per profile

| Profile ID | Skill Policy | PvP Aggression |
|---|---|---|
| stage_guard_opportunist (Cautious) | immediate reserve=30 | 0.10 |
| greed_desperate (Risk Taker) | specialize priority=[upcycling,prospecting] reserve=10 | 0.35 |
| value_hoarder (Hoarder) | never | 0.05 |
| fixed_highest (Measured) | specialize priority=[selling] reserve=30 | 0.15 |
| instability_loyalist (Loyalist) | specialize priority=[upcycling] reserve=20 | 0.25 |
| fixed_loyalist (Fixed Loyalist) | specialize priority=[selling] reserve=20 | 0.20 |
| stage_loyalist (Stage Loyalist) | immediate reserve=30 | 0.15 |
| greed_loyalist (Greedy Loyalist) | specialize priority=[upcycling,prospecting] reserve=10 | 0.30 |
| value_loyalist (Value Loyalist) | specialize priority=[selling] reserve=30 | 0.10 |

Note: Solitary (smuggling) is intentionally absent from specialize priority lists. Only immediate-policy bots may buy it. This can be revisited if Black Market becomes more central.

**Verify**: YAML parses cleanly

### Step 6: Update simulate command
**File**: lib/MagicMountain/Command/simulate.pm
- Remove skill_profile handling and --skill-profile flag from GetOptionsFromArray and usage
- Replace the fallback profile (lines 89-96) with skill_policy => { name => 'never' } and pvp_aggressiveness => 0.10
- Character creation sets initial skill levels to 0 unconditionally (remove fallback to %skill_defaults)
- In bot roster metadata: replace skills => $p->{skill_profile} with skill_policy => $p->{skill_policy}

**Verify**: perl -Ilib script/mountain simulate --count 3 --days 5 runs cleanly and produces transcript with skill_purchase events

### Step 7: Run baseline simulation and report
- Run a full 30-day simulation with updated profiles
- Run perl -Ilib script/mountain report --transcript PATH to verify skill purchases and PvP counts

**Verify**: Bots spend scrap on skills; pressure_applied_bot events increase above current 9-event baseline

## Test Summary

| Test | What it covers |
|---|---|
| test_skill_policy_immediate | Buys cheapest affordable skill, respects reserve |
| test_skill_policy_specialize | Maxes priority tree before switching, ignores out-of-priority skills |
| test_skill_policy_never | Never buys, even with abundant scrap |
| test_skill_policy_reserve | Skips purchase when scrap - cost < reserve |
| test_skill_policy_unknown_defaults_to_never | Typo policy name silently falls back |
| test_skill_policy_missing_defaults_to_never | No skill_policy in profile defaults safely |
| test_skill_training_transcript_log | SkillTraining::purchase fires log_event on success |
| test_botrunner_skill_buying | BotRunner buys skill during run_day, logs policy_skill_purchase |
| test_botrunner_skill_buying_cap | BotRunner caps at 1 purchase per day |
