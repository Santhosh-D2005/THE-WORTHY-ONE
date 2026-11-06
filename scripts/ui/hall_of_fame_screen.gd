class_name HallOfFameScreen
extends OverlayScreen
## The Hall of Fame: one screen with an ENDLESS tab and a RUTHLESS tab. Online it shows the world board. Offline it shows this device's own
## best in that mode (marked as local), because the world board needs a connection. It only DISPLAYS what the server returns (rank, name, level,
## time, "is me", and the player's own place even when it is off the page). Nothing is calculated, cached or invented on the device: with no
## answer it says so. Pages of 10 with PREV / NEXT (no scrolling needed on a touch screen), REFRESH, and a request is never sent twice at
## once; a late answer for a tab or page the player has already left is ignored.
## Names are shown with plain Labels (no markup), trimmed to their column, so a name can never inject formatting.

const PAGE_SIZE := 10

## (mode: GameMode.Mode, limit: int, offset: int) -> Dictionary (a coroutine). Tests replace it.
var fetcher: Callable = func(mode: GameMode.Mode, limit: int, offset: int) -> Dictionary: return await Backend.leaderboard(mode, limit, offset)

var mode: GameMode.Mode = GameMode.Mode.ENDLESS
var view_state: String = "idle"   # idle | loading | ready | empty | offline | error
var requests_sent: int = 0
var _local_note: String = ""

var _offset: int = 0
var _total: int = 0
var _serial: int = 0
var _loading: bool = false
var _tab_endless: Button
var _tab_ruthless: Button
var _message: Label
var _rows: Array[Dictionary] = []
var _me_label: Label
var _page_label: Label
var _prev: Button
var _next: Button
var _refresh: Button

func screen_title() -> String:
	return "HALL OF FAME"

func _build_content(parent: VBoxContainer) -> void:
	var tabs := HBoxContainer.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_theme_constant_override("separation", 16)
	parent.add_child(tabs)
	_tab_endless = make_button("ENDLESS", false, "TabEndless", 34, 100)
	_tab_ruthless = make_button("RUTHLESS", false, "TabRuthless", 34, 100)
	tabs.add_child(_tab_endless)
	tabs.add_child(_tab_ruthless)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(header)
	for spec in [["RANK", 110, false], ["PLAYER", 0, true], ["LEVEL", 130, false], ["TIME", 170, false]]:
		var caption := make_label(spec[0], 24, UiStyle.CAPTION, false)
		caption.custom_minimum_size = Vector2(spec[1], 0)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL if spec[2] else Control.SIZE_FILL
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if spec[2] else HORIZONTAL_ALIGNMENT_CENTER
		header.add_child(caption)
	_message = make_label("", 32, UiStyle.PARCHMENT_DIM)
	_message.name = "Message"
	_message.custom_minimum_size = Vector2(0, 120)
	parent.add_child(_message)
	var list := VBoxContainer.new()
	list.name = "Rows"
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 6)
	parent.add_child(list)
	for i in PAGE_SIZE:
		var row := HBoxContainer.new()
		row.name = "Row%d" % i
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rank := make_label("", 30, UiStyle.PARCHMENT, false)
		rank.custom_minimum_size = Vector2(110, 54)
		var player := make_label("", 30, UiStyle.PARCHMENT, false)
		player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		player.clip_text = true
		player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var level := make_label("", 30, UiStyle.PARCHMENT, false)
		level.custom_minimum_size = Vector2(130, 0)
		var time := make_label("", 26, UiStyle.PARCHMENT_DIM, false)
		time.custom_minimum_size = Vector2(170, 0)
		for label in [rank, player, level, time]:
			row.add_child(label)
		list.add_child(row)
		_rows.append({"row": row, "rank": rank, "name": player, "level": level, "time": time})
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)
	_me_label = make_label("", 30, UiStyle.GOLD_BRIGHT)
	_me_label.name = "MyPlace"
	_me_label.custom_minimum_size = Vector2(0, 70)
	parent.add_child(_me_label)
	var pager := HBoxContainer.new()
	pager.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pager.add_theme_constant_override("separation", 12)
	parent.add_child(pager)
	_prev = make_button("PREV", false, "PrevButton", 32, 100)
	_page_label = make_label("", 28, UiStyle.PARCHMENT_DIM, false)
	_page_label.custom_minimum_size = Vector2(190, 0)
	_next = make_button("NEXT", false, "NextButton", 32, 100)
	_refresh = make_button("REFRESH", false, "RefreshButton", 30, 100)
	for node in [_prev, _page_label, _next, _refresh]:
		pager.add_child(node)

func open_for(new_mode: GameMode.Mode) -> void:
	mode = new_mode
	_offset = 0
	open()
	_serial += 1
	_loading = false
	_load()

func _on_opened() -> void:
	_set_view("loading")

func _ready() -> void:
	super._ready()
	closed.connect(func() -> void:
		_serial += 1  # an answer still on its way is now stale
		_loading = false)

func _on_action(button: Button) -> void:
	if button == _tab_endless:
		_switch(GameMode.Mode.ENDLESS)
	elif button == _tab_ruthless:
		_switch(GameMode.Mode.RUTHLESS)
	elif button == _prev:
		_go(_offset - PAGE_SIZE)
	elif button == _next:
		_go(_offset + PAGE_SIZE)
	elif button == _refresh:
		_load()

func _switch(new_mode: GameMode.Mode) -> void:
	if new_mode == mode and view_state != "error" and view_state != "local":
		return
	mode = new_mode
	_offset = 0
	_serial += 1
	_loading = false
	_load()

func _go(new_offset: int) -> void:
	if _loading or new_offset < 0 or (new_offset >= _total and view_state == "ready"):
		return
	_offset = new_offset
	_load()

## Ask the server for the current page. Does nothing while a request is already on its way.
func _load() -> void:
	if _loading:
		return
	_loading = true
	var mine := _serial
	var asked_mode := mode
	var asked_offset := _offset
	_set_view("loading")
	requests_sent += 1
	var reply: Dictionary = await fetcher.call(asked_mode, PAGE_SIZE, asked_offset)
	if mine != _serial or not is_showing:
		return  # the player moved on: this answer is stale
	_loading = false
	if not reply.get("ok", false):
		var error := str(reply.get("error", "error"))
		if error in Backend.NETWORK_ERRORS:
			_show_local()
		else:
			_set_view("error", error)
		return
	_total = maxi(int(reply.get("total", 0)), 0)
	var entries: Array = reply.get("entries", []) if reply.get("entries", []) is Array else []
	if entries.is_empty() and _total > 0 and _offset > 0:
		_offset = 0  # the board shrank under us: back to the first page
		_load()
		return
	_show_entries(entries, reply.get("me"))
	_set_view("empty" if _total == 0 else "ready")

## Offline: this device's best in the current mode, as a one-row board. Nothing is invented: no record means an honest empty note.
func _show_local() -> void:
	var best: Dictionary = Progress.best(mode)
	var level := int(best.get("best_level", 0))
	if level > 0:
		_total = 1
		var name := Account.username if Account.logged_in and Account.username != "" else "You (this device)"
		_show_entries([{"rank": 1, "name": name, "level": level, "seconds": float(best.get("best_seconds", 0.0)), "is_me": true}], null)
		_me_label.text = "THIS DEVICE ONLY. The world Hall of Fame returns when you are online."
		_local_note = "You are offline. Showing your best on this device."
	else:
		_total = 0
		_show_entries([], null)
		_me_label.text = ""
		_local_note = "You are offline, and no sword has been drawn in this mode on this device yet. The world Hall of Fame returns when you are online."
	_set_view("local")

func _show_entries(entries: Array, me: Variant) -> void:
	for i in PAGE_SIZE:
		var slot: Dictionary = _rows[i]
		var has := i < entries.size() and entries[i] is Dictionary
		(slot["row"] as Control).visible = has
		if not has:
			continue
		var entry: Dictionary = entries[i]
		var mine := bool(entry.get("is_me", false))
		var color := UiStyle.GOLD_BRIGHT if mine else UiStyle.PARCHMENT
		(slot["rank"] as Label).text = "#%d" % int(entry.get("rank", 0))
		(slot["name"] as Label).text = str(entry.get("name", "?"))
		(slot["level"] as Label).text = str(int(entry.get("level", 0)))
		(slot["time"] as Label).text = RunResult.format_time(float(entry.get("seconds", 0.0)))
		for key in ["rank", "name", "level"]:
			(slot[key] as Label).add_theme_color_override("font_color", color)
	if me is Dictionary:
		_me_label.text = "YOUR PLACE  #%d   LEVEL %d   %s" % [int(me.get("rank", 0)), int(me.get("level", 0)), RunResult.format_time(float(me.get("seconds", 0.0)))]
	else:
		_me_label.text = "YOU HAVE NOT YET CLAIMED A PLACE"

func _set_view(new_state: String, error: String = "") -> void:
	view_state = new_state
	var showing_rows := new_state == "ready" or new_state == "local"
	for slot in _rows:
		if not showing_rows:
			(slot["row"] as Control).visible = false
	match new_state:
		"loading":
			_message.text = "Consulting the record..."
		"empty":
			_message.text = "No one has claimed a place here yet."
			_me_label.text = ""
		"local":
			_message.text = _local_note
		"error":
			_message.text = "The Hall of Fame could not be reached (%s). Try again in a moment." % error
			_me_label.text = ""
		_:
			_message.text = ""
	_message.visible = new_state != "ready"
	_me_label.visible = new_state == "ready" or new_state == "local"
	var pages := maxi(int(ceil(float(_total) / PAGE_SIZE)), 1)
	_page_label.text = "PAGE %d / %d" % [_offset / PAGE_SIZE + 1, pages] if new_state == "ready" else ""
	_prev.disabled = new_state != "ready" or _offset <= 0
	_next.disabled = new_state != "ready" or _offset + PAGE_SIZE >= _total
	_refresh.disabled = new_state == "loading"
	for pair in [[_tab_endless, GameMode.Mode.ENDLESS], [_tab_ruthless, GameMode.Mode.RUTHLESS]]:
		(pair[0] as Button).modulate = Color(1, 1, 1, 1) if pair[1] == mode else Color(1, 1, 1, 0.5)
	title_label.text = "%s HALL OF FAME" % GameMode.title(mode)
