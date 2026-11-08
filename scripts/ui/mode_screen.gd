class_name ModeScreen
extends OverlayScreen
## "CHOOSE YOUR TRIAL": Endless or Ruthless, what each means, the player's own best in each (from the local save, never invented), a
## button to begin and a button to open that mode's Hall of Fame. It only emits signals; the menu starts the game.

signal mode_chosen(mode: GameMode.Mode)
signal hall_requested(mode: GameMode.Mode)

const DESCRIPTIONS := {
	GameMode.Mode.ENDLESS: "No ceiling. Every sword drawn brings a harder one. A failed pull ends the run, and your best is always kept.",
	GameMode.Mode.RUTHLESS: "The same road with no mercy: a harder wood from the first sword. Failing, or leaving the game for any reason, ends the run on the spot. A run can never be resumed.",
}

var _best_labels := {}
var _buttons := {}

func screen_title() -> String:
	return "CHOOSE YOUR TRIAL"

func _build_content(parent: VBoxContainer) -> void:
	for mode_value in [GameMode.Mode.ENDLESS, GameMode.Mode.RUTHLESS]:
		var mode: GameMode.Mode = mode_value
		var name := GameMode.title(mode)
		var heading := make_label(name, 56, UiStyle.GOLD_BRIGHT, false)
		heading.name = "%sHeading" % name.capitalize()
		parent.add_child(heading)
		parent.add_child(make_label(DESCRIPTIONS[mode], 30, UiStyle.PARCHMENT))
		var best := make_label("", 28, UiStyle.CAPTION, false)
		best.name = "%sBest" % name.capitalize()
		parent.add_child(best)
		_best_labels[mode] = best
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 14)
		parent.add_child(row)
		var begin := make_button("BEGIN", true, "Begin%s" % name.capitalize(), 40, 120)
		begin.size_flags_stretch_ratio = 1.4
		var hall := make_button("HALL OF FAME", false, "Hall%s" % name.capitalize(), 30, 120)
		row.add_child(begin)
		row.add_child(hall)
		_buttons[begin] = [mode, true]
		_buttons[hall] = [mode, false]
		var gap := Control.new()
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gap.custom_minimum_size = Vector2(0, 24)
		parent.add_child(gap)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)

func _on_opened() -> void:
	for mode_value in _best_labels:
		var mode: GameMode.Mode = mode_value
		var best := Progress.best(mode)
		if mode == GameMode.Mode.ENDLESS:
			(_best_labels[mode] as Label).text = "CONTINUE FROM LEVEL %d" % Progress.start_level_for(mode)
		else:
			(_best_labels[mode] as Label).text = "YOUR BEST: LEVEL %d" % int(best["best_level"]) if int(best["best_level"]) > 0 else "NO SWORD DRAWN YET"

func begin_button(mode: GameMode.Mode) -> Button:
	return _find(mode, true)

func hall_button(mode: GameMode.Mode) -> Button:
	return _find(mode, false)

func _find(mode: GameMode.Mode, begin: bool) -> Button:
	for button: Button in _buttons:
		if _buttons[button][0] == mode and _buttons[button][1] == begin:
			return button
	return null

func _on_action(button: Button) -> void:
	if not _buttons.has(button):
		return
	var spec: Array = _buttons[button]
	if spec[1]:
		mode_chosen.emit(spec[0])
	else:
		hall_requested.emit(spec[0])
