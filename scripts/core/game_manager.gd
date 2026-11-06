extends Node
## Autoload "GameManager": owns the global game state machine and the current run.
## (Doubles as GameStateManager for now; split out if the state logic grows.)
## Other systems talk to it through signals and never reach into each other directly.

enum State {
	READY,       ## Level loaded, waiting for the first valid tap. The player cannot fail here.
	PLAYING,     ## Player is actively extracting. Progress reaching 0 now ends the run.
	EXTRACTING,  ## Success animation running; input locked.
	PAUSED,      ## Tree paused (menu, focus loss).
	FAILED,      ## The run has ended in failure; waiting for TRY AGAIN / MAIN MENU.
}

## The last level of the game. Completing it finishes the run (there is no level 10000).
const MAX_LEVEL := 9999

signal state_changed(new_state: State)
signal level_changed(new_level: int)
## Emitted once per success, before the level counter advances.
signal extraction_succeeded(level: int, extraction_time_seconds: float)
## Emitted exactly once per failed run, after the timers are frozen.
signal run_failed(result: RunResult)

var state: State = State.READY
var level: int = 1
## Swords extracted in the current run (reset by reset_run()).
var run_extractions: int = 0
## True from the moment a run fails until reset_run(). Guards against duplicate failures.
var run_over: bool = false
## The most recent finished run (null until one ends).
var last_result: RunResult = null

var _state_before_pause: State = State.READY

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	extraction_succeeded.connect(func(_level: int, _time: float) -> void: run_extractions += 1)

func set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)

func advance_level() -> void:
	level += 1
	level_changed.emit(level)

## Start a fresh run: level 1, no extractions, not over. Lifetime records are NOT touched
## (none exist yet; when they do they live outside this object).
func reset_run() -> void:
	level = 1
	run_extractions = 0
	run_over = false
	last_result = null
	level_changed.emit(level)

func is_input_allowed() -> bool:
	return state == State.READY or state == State.PLAYING

## The single gate for failure. Returns true exactly once per run, and only while the player
## is actively extracting (PLAYING): never before the first valid tap (READY), never during
## the success animation (EXTRACTING), never while paused, never twice.
func begin_failure() -> bool:
	if state != State.PLAYING or run_over:
		return false
	run_over = true
	set_state(State.FAILED)  # input is disabled synchronously by the state change
	return true

func publish_run_result(result: RunResult) -> void:
	last_result = result
	run_failed.emit(result)

func pause_game() -> void:
	if state == State.PAUSED:
		return
	_state_before_pause = state
	set_state(State.PAUSED)
	get_tree().paused = true

func resume_game() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	set_state(_state_before_pause)
