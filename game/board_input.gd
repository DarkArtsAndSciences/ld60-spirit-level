extends Node
## The Wii Balance Board, for any Godot game: add this file as an autoload named "Board"
## (Project > Project Settings > Globals > Autoload).
##
## It connects to tools/balance-board/board_server.py on this Mac, which gets the readings
## from the 2011 MacBook Air. Works in the editor (Cmd+B), in a desktop build, and in a web
## build opened from http://localhost. If the server isn't running, it quietly keeps trying,
## and Board.active stays false, so the game falls back to tilt or the keyboard.
##
## Read these from anywhere, every frame:
##   Board.direction  Vector2: a unit vector while the player leans on purpose, ZERO while
##                    they stand still. Screen convention, like Input.get_vector(): x right,
##                    y DOWN (leaning toward the toes is up the screen, -y). Use it the way
##                    you use the keyboard: steer while it isn't zero, coast while it is.
##   Board.stick      Vector2: the same lean as an analog stick, length 0..1 (0 inside the
##                    still zone), same convention. For when how far you lean should matter.
##   Board.active     true while someone is standing on a connected board
##   Board.settled    true once they've settled after stepping on (direction is ZERO before)
##   Board.lean       Vector2, raw centre of balance, each axis -1..1, in the BOARD's frame:
##                    x right, y toward the toes (+). Unfiltered.
##   Board.corners    kilograms on each corner: {"tl", "tr", "bl", "br"}
## Board.recenter() makes the current position "level" (stepping off and on does the same).

const URL := "ws://127.0.0.1:8765/ws"

## Flip these if the dot goes the wrong way (it depends which way the player faces), from
## any script: Board.flip_x = true
var flip_x := false
var flip_y := false

var active := false
var connected := false
var settled := false
var lean := Vector2.ZERO
var direction := Vector2.ZERO
var stick := Vector2.ZERO
var corners := {"tl": 0.0, "tr": 0.0, "bl": 0.0, "br": 0.0}

var feel := Feel.new()
var _ws := WebSocketPeer.new()
var _retry_in := 0.0
var _last_reading_ms := 0


func _ready() -> void:
	# Online (itch.io, ldjam) there's no board server, and an HTTPS page isn't allowed to open
	# ws:// anyway: every retry would put an error in the player's console. So in a browser,
	# only look for the board when the game itself was opened from this Mac.
	if OS.has_feature("web"):
		var host = JavaScriptBridge.eval("location.hostname", true)
		if host != "localhost" and host != "127.0.0.1":
			set_process(false)
			return
	_ws.connect_to_url(URL)


func recenter() -> void:
	feel.recenter()


func _process(delta: float) -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	connected = state == WebSocketPeer.STATE_OPEN
	if state == WebSocketPeer.STATE_CLOSED:
		_clear()
		_retry_in -= delta
		if _retry_in <= 0.0:
			_retry_in = 2.0
			_ws.connect_to_url(URL)
		return
	while _ws.get_available_packet_count() > 0:
		var msg = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
		if msg is Dictionary and msg.has("x"):
			_read(msg)
		elif msg is Dictionary and msg.has("info"):
			print("Board: ", msg.info)
	if Time.get_ticks_msec() - _last_reading_ms > 500:   # board off or out of range
		_clear()


func _read(m: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var dt := clampf((now - _last_reading_ms) / 1000.0, 0.001, 0.2)
	_last_reading_ms = now
	corners = {"tl": m.tl, "tr": m.tr, "bl": m.bl, "br": m.br}
	lean = Vector2(-m.x if flip_x else m.x, -m.y if flip_y else m.y)
	feel.update(lean, m.total, dt)
	active = feel.on_board
	settled = feel.settled
	stick = feel.stick
	direction = feel.direction


func _clear() -> void:
	active = false
	settled = false
	direction = Vector2.ZERO
	stick = Vector2.ZERO


## Turns a stream of raw readings into intent: still or leaning, and which way.
## Separate from the networking so the replay test (test_board_feel.gd) can drive it.
class Feel:
	# Everything is tunable. Lengths are in the board's -1..1 units.
	var on_board_kg := 10.0        # less than this is nobody on the board
	var smoothing := 0.08          # seconds; low-pass filter on the raw lean (sensor jitter)
	var settle_time := 0.4         # seconds of steady weight after stepping on before "level" is taken
	var settle_wobble := 0.03      # "steady" = weight within 3% of its recent average
	# How far people can lean each way from where they stand (measured 2026-10-16:
	# right/left ~0.4-0.55, toes ~0.6-0.7, heels ~0.35). A lean of this size is a full stick.
	var reach_right := 0.40
	var reach_left := 0.40
	var reach_toes := 0.50
	var reach_heels := 0.30
	# Hysteresis, as a fraction of reach: start moving above `start`, stop below `stop`.
	# Standing sway measured about +-0.07 (~0.18 of reach), so `stop` sits just above it.
	var start := 0.30
	var stop := 0.20
	# Inside the still zone (under `stop`), "level" follows where you stand, with this time
	# constant in seconds. Outside it, it doesn't: a held lean keeps going, and a slow
	# deliberate lean still gets out past `start` because "level" stops chasing it at `stop`.
	var follow := 2.0

	var on_board := false
	var settled := false
	var moving := false
	var base := Vector2.ZERO       # "level": where the player stands when not leaning
	var smooth := Vector2.ZERO
	var stick := Vector2.ZERO      # screen convention (y down), length 0..1
	var direction := Vector2.ZERO  # screen convention, unit or ZERO

	var _weights: Array[float] = []
	var _steady_for := 0.0
	var _steady_sum := Vector2.ZERO   # lean summed over the steady stretch, for "level"
	var _steady_n := 0

	func recenter() -> void:
		base = smooth

	func update(raw: Vector2, weight: float, dt: float) -> void:
		var was_on := on_board
		on_board = weight > on_board_kg
		if not on_board:
			settled = false
			moving = false
			_weights.clear()
			_steady_for = 0.0
			_steady_sum = Vector2.ZERO
			_steady_n = 0
			stick = Vector2.ZERO
			direction = Vector2.ZERO
			return
		if not was_on:
			smooth = raw

		var k := 1.0 - exp(-dt / smoothing)
		smooth += (raw - smooth) * k

		if not settled:
			_weights.append(weight)
			if _weights.size() > 30:
				_weights.pop_front()
			var avg := 0.0
			for w in _weights:
				avg += w
			avg /= _weights.size()
			if absf(weight - avg) < avg * settle_wobble:
				_steady_for += dt
				_steady_sum += smooth
				_steady_n += 1
			else:
				_steady_for = 0.0
				_steady_sum = Vector2.ZERO
				_steady_n = 0
			if _steady_for >= settle_time:
				settled = true
				base = _steady_sum / _steady_n   # the average stance, not one moment of sway
			stick = Vector2.ZERO
			direction = Vector2.ZERO
			return

		var rel := smooth - base
		var n := Vector2(
			rel.x / (reach_right if rel.x > 0.0 else reach_left),
			rel.y / (reach_toes if rel.y > 0.0 else reach_heels))
		var amount := n.length()
		if moving and amount < stop:
			moving = false
		elif not moving and amount > start:
			moving = true

		if not moving and amount < stop:
			base += (smooth - base) * (1.0 - exp(-dt / follow))

		if moving:
			var strength := clampf((amount - stop) / (1.0 - stop), 0.0, 1.0)
			var screen := Vector2(n.x, -n.y).normalized()
			direction = screen
			stick = screen * strength
		else:
			direction = Vector2.ZERO
			stick = Vector2.ZERO
