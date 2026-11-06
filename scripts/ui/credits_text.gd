class_name CreditsText
extends RefCounted
## The credits text (who made THE WORTHY ONE and what it is built with, with the licence notes third-party work requires), and the
## function that lays it out. SettingsScreen shows it as its CREDITS page, so it fits one panel and needs no scrolling (a touch scroll
## is not verified on the phone yet).

const ENTRIES := [
	["GAME DESIGN, CODE AND TESTING", "Santhosh-D2005"],
	["MADE WITH", "Godot Engine 4.7, an open-source engine (MIT licence)"],
	["TYPEFACE", "Cinzel by The Cinzel Project Authors. SIL Open Font License 1.1 (assets/fonts/OFL-Cinzel.txt)"],
	["SOUND", "Every sound was synthesised for this game and is released under CC0 1.0 (public domain). See assets/audio/README.md"],
	["ONLINE HALL OF FAME", "Account and leaderboard service: Supabase"],
]

static func build(parent: VBoxContainer) -> void:
	var name_label := _label("THE WORTHY ONE", 52, UiStyle.GOLD_BRIGHT)
	name_label.name = "GameName"
	parent.add_child(name_label)
	parent.add_child(_label("One sword. One tree. One challenge.", 28, UiStyle.CAPTION))
	for entry in ENTRIES:
		var key := str(entry[0]).replace(" ", "_").replace(",", "")
		var heading := _label(entry[0], 26, UiStyle.GOLD)
		heading.name = "Heading_" + key
		parent.add_child(heading)
		var body := _label(entry[1], 30, UiStyle.PARCHMENT)
		body.name = "Body_" + key
		parent.add_child(body)
	var thanks := _label("Thank you for playing.", 32, UiStyle.GOLD_BRIGHT)
	thanks.name = "Thanks"
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(thanks)

static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := UiStyle.label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
