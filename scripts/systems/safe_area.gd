class_name SafeArea
extends RefCounted
## Screen insets (camera cut-out / status bar at the top, gesture bar at the bottom) expressed in
## the game's base viewport pixels, so HUD elements can stay clear of them.
##
## On desktop (window smaller than the screen) and on any device that reports no insets the
## result is zero, so layouts are unchanged. On Android, when the game window fills the screen,
## DisplayServer.get_display_safe_area() describes the usable region.

## Tests set this (Vector4: left, top, right, bottom in viewport px) to simulate a notch and a
## gesture bar. null = use the real display values.
static var test_insets: Variant = null

## (left, top, right, bottom) in base-viewport pixels.
static func insets_in_viewport(viewport: Viewport) -> Vector4:
	if test_insets != null:
		return test_insets
	var window_size := DisplayServer.window_get_size()
	var screen_size := DisplayServer.screen_get_size()
	if window_size.x <= 0 or window_size != screen_size:
		return Vector4.ZERO  # windowed (desktop) or not full-screen: the OS already lays us out
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var scale := viewport.get_visible_rect().size.x / float(window_size.x)
	return Vector4(
		maxf(0.0, float(safe.position.x)),
		maxf(0.0, float(safe.position.y)),
		maxf(0.0, float(screen_size.x - safe.end.x)),
		maxf(0.0, float(screen_size.y - safe.end.y))) * scale
