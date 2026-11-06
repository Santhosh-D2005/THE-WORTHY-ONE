class_name ProgressFormat
extends RefCounted
## How progress is shown as a whole-number percentage (kept apart from the HUD so it can be unit-tested headless).

## floor(progress), and 100 only when the bar is really full. Never rounds up, so the label can never show 100 %
## - or a number ahead of the real progress - early.
static func percent_for(progress: float) -> int:
	if progress >= 99.9999:
		return 100
	return mini(99, int(floor(progress + 0.000001)))
