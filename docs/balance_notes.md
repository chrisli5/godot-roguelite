# Balance notes: hit vs DoT specialization
 
Source: `effective_dps_hit_vs_dot.xlsx` (sheets Assumptions, Results, Rule Tests, Scenarios, Sim_DoT, Sim_Total).
Status: analysis only. **Every number here is a placeholder**, not tuned game data. Nothing in this file is implemented in the game yet.
 
## Goal
 
Both specializations must be viable, and hit scaling must not be the best investment for both builds.
- Hit build: hit-damage cards, Lightning (crit chance), Frost (cooldown).
- DoT build: DoT-damage cards, Fire (DoT damage and duration), Frost (cooldown).
- Hybrid: an even split.
## Fixed rules the model assumes (match CLAUDE.md)
 
- Hit damage reads `BASE_DAMAGE` plus crit. DoT reads its own `DOT_DAMAGE` and `STATUS_DURATION`. DoT never reads `BASE_DAMAGE`, and DoT ticks never crit.
- Burn ramps with time active (+10% per second, capped at 5 s). Stacking policy is REFRESH.
- Infusion tiers past the soft cap of 5 are damped 20% per tier.
- Pass criterion: at 12 drafts, each build's own-channel card beats the other channel's card, at Swarm (3 s), Elite (10 s) and Boss (30 s) exposure, with DoT/Hit within 1 +/- 15%.
## Findings
 
1. **Additive pools fail.** With additive card pools, a hit card helps the DoT build almost as much as a DoT card, and in the baseline the DoT build's own card loses at all three fight lengths. This is what motivated the multiplicative rule.
2. **Multiplicative pools pass.** Each pool contributes (1 + v)^cards. This passed all six specialization checks (DoT and Hit builds at Swarm, Elite and Boss) with the Fire value at 1.63 DoT/s per tier. This is the structural rule to implement first.
3. **Mono-channel bonus and Fire hit tax are optional extras.**
   - Neither alone fixes additive pools.
   - Mono + Tax together pass on additive pools (Fire 1.93).
   - Adding either to multiplicative pools widens the DoT build's margin (+6.1 points with Mono, +5.6 with Tax, +7.8 with all three, versus +3.4 for multiplicative alone at Elite).
   - Treat them as later tuning layers, not launch requirements.
4. **Fire value is a tuning knob, not a free parameter.** At Fire 3.0 DoT per tier, the DoT build ran 40-70% ahead of the hit build. Each rule set in the workbook carries its own pre-solved Fire value so DoT/Hit = 1.00 at Elite and 12 drafts:
   | Rule set | Pools | Mono | Tax | Fire DoT/s per tier |
   |---|---|---|---|---|
   | Baseline | Additive | Off | Off | 1.49 |
   | Multiplicative | Multiplicative | Off | Off | 1.63 |
   | Mono | Additive | On | Off | 1.76 |
   | Tax | Additive | Off | On | 1.71 |
   | Mult + Mono | Multiplicative | On | Off | 1.86 |
   | Mult + Tax | Multiplicative | Off | On | 1.82 |
   | Mono + Tax | Additive | On | On | 1.93 |
   | All three | Multiplicative | On | On | 2.02 |
5. **DoT edges ahead in long fights.** At 12 drafts the DoT/Hit ratio is about 0.89 at Swarm, 1.00 at Elite and 1.05 at Boss. Short fights favor hit builds because burn has less time to ramp.
6. **Known weak spots.**
   - Early drafts (4 and 8) still fail the specialization test.
   - DoT/Hit drifts from about 1.02 at 4 drafts to about 0.80 at 20 drafts at a fixed Fire value, so Fire needs a value curve across a run (open item).
   - STACK stacking policy multiplies DoT output roughly two to four times at the placeholder values. Keep REFRESH until the numbers are re-tuned.
## Model limits (do not over-trust)
 
- Single target, one ability. No area, spreading, chain or multi-target effects, so Earth and Wind are not modeled. Swarm results reflect short exposure, not crowds.
- Frost and Wind indirect damage scaling are omitted (still proof of concept).
- No overkill, enemy death or movement. Short fights are sensitive to cast timing (first cast at t = 0), so read Swarm as indicative.
- A DoT card does nothing without a Fire tier.
- Time step is 0.25 s. Fight lengths must be multiples of it, up to 240 steps.
## Differences between the workbook and the current design
 
- The workbook gives Lightning both a crit chance tier (+5%) and a crit multiplier tier (+0.15). The design now says a Lightning definition holds one stat modifier carrying **crit chance only**. Where crit multiplier comes from is an open item. Re-run the Hit build with the multiplier tier removed before trusting hit-side numbers.
- The workbook uses relative units (base damage 10). Arcane Bolt currently ships with base damage 1.0 and no crit stats.
## How to re-run
 
Change only the blue input cells on the Assumptions sheet. After changing other inputs, re-solve each rule set's Fire value with Goal Seek on the Elite DoT/Hit cell of Rule Tests (target 1.00), otherwise tuning will confound the comparison.
 
## Open questions this analysis leaves
 
- A Fire value curve across a run, so DoT/Hit does not drift as drafts accumulate.
- Whether early-game specialization (4 to 8 drafts) needs a mono-channel bonus or a different fix.
- Where Lightning's crit multiplier comes from.
- Re-tuning before switching Burn to STACK.