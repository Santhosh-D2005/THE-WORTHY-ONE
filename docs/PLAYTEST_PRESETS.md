# Playtest difficulty presets

**Updated for Milestone 1.9 (speed-based extraction).** There is NO fixed tap count any more: progress per tap depends on the measured interval between alternating taps (`SpeedGain`). Parameters in `DifficultyConfig`: `start/end_peak_gain`, `optimal_interval_msec`, `useful_fraction`, `gain_curve_exponent`, `start/end_max_tap_interval_msec`, `start/end_resistance`, decay and grace (unchanged). The full level 1-30 table is in `MILESTONE_1_9_REPORT.md`; `tools/difficulty_table.gd` prints it. The presets set `start/end_peak_gain` (and their own gaps, resistance, decay, grace).

**Milestone 1.8 text (superseded: it described the fixed tap table):** The default now needs exactly 15, 17, 20 ... 46 taps on levels 1-10 (`required_taps_table`, editable; empty = start/end curve), gap 400 -> 230 ms, decay/grace unchanged. Older text below describes 1.7.

**Milestone 1.7 text:** Progress is now defined by the number of successful taps needed (`start/end_required_taps`, gain = 100 / taps),
not by a gain percentage. The shipped balance (`default_difficulty.tres`): level 1 = 50 taps (2 % per tap), 330 ms gap, 0.5 s grace, 5 %/s decay;
level 30 = 192 taps, 217 ms gap, 0.27 s grace, 13 %/s decay. The full per-level table is in `MILESTONE_1_7_REPORT.md`.
The preset table that used to be here listed the old 8 %-per-tap numbers and is no longer valid; open the `.tres` file of a preset for its values.

Gain, decay delay (grace) and decay rate are independent. Each has its own start value, end value and (optional)
own curve speed (`gain_ramp_levels`, `decay_ramp_levels`, `grace_ramp_levels`; 0 = follow `ramp_levels`).
Changing one never changes the other two (covered by unit tests).

Pick a preset with `--difficulty-preset=<name>` (see `docs/ANDROID_EXPORT.md`), or edit the `.tres` files in the inspector.
The retry lock after TRY AGAIN is separate: `resources/configuration/default_gameplay.tres`, default 0.4 s (0 = off).

## Parameters (1.7)

Three independent difficulty parameters, each with its own start, end and ramp length (changing one never changes another):

| Parameter | Fields |
|---|---|
| A. successful taps needed | `start_required_taps`, `end_required_taps`, `required_taps_ramp_levels` |
| B. maximum gap between taps | `start/end_max_tap_interval_msec`, `interval_ramp_levels` |
| C. extraction resistance (progress gets harder near the top) | `start/end_resistance`, `resistance_ramp_levels` |

Decay (`start/end_decay`) and grace (`start/end_grace`) keep their 1.4 curves. Rules: the first tap of an attempt awards 0; a tap slower than the gap
awards 0; two taps on the same side award 0. `GameplayConfig.rhythm_enabled = false` and `max_tap_interval_override_msec` still work.
