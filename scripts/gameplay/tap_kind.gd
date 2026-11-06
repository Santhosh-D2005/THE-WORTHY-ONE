class_name TapKind
extends RefCounted
## What an accepted tap means for the rhythm rule (kept in its own file, like TapSide).

enum Kind {
	FIRST,     ## First tap of an attempt (or after a pause): starts the attempt and anchors the rhythm. No progress.
	PROGRESS,  ## Alternating tap that arrived within the allowed interval: awards progress.
	TOO_SLOW,  ## Alternating tap, but too long after the previous one: no progress; it becomes the new anchor.
}
