extends Node2D
class_name Game

const TILT_JS := """
(() => {
	window.tilt = { gamma: null, beta: null, state: "no readings yet" };
	
	const onTilt = (e) => {
		if (e.gamma == null) return;
		tilt.gamma = e.gamma; tilt.beta = e.beta; tilt.state = "reading";
	};
	addEventListener("deviceorientation", onTilt);
	
	const D = window.DeviceOrientationEvent;
	if (D && typeof D.requestPermission === "function") {
		tilt.framed = window.self !== window.top;
		if (tilt.framed) {
			tilt.state = "tap to escape frame";
			const escape = () => {
				removeEventListener("touchend", escape); removeEventListener("click", escape);
				window.open(location.href, "_blank");
			};
			addEventListener("touchend", escape); addEventListener("click", escape);
		} else {
			tilt.state = "tap to allow motion";
			const ask = () => {
				removeEventListener("touchend", ask); removeEventListener("click", ask);
				D.requestPermission()
				.then((s) => { tilt.state = s; addEventListener("deviceorientation", onTilt); })
				.catch((err) => { tilt.state = "error: " + err.name; });
			};
			addEventListener("touchend", ask); addEventListener("click", ask);
		}
	}
})();
"""

var tilt:JavaScriptObject = null  # the JS object, null if not in a browser
func setup_tilt_bridge() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(TILT_JS, true)
		tilt = JavaScriptBridge.get_interface("tilt")
		print("setup tilt: " + tilt.state)

var screen_center := Vector2.ZERO
# TODO: make sure this gets called on resize / fullscreen
func reset_screen() -> void:
	screen_center = get_viewport_rect().size / 2
	print("screen size: %d %d" % [screen_center.x, screen_center.y])

var dot_pos := Vector2.ZERO
var level := 0
func reset_level(next_level: int) -> void:
	level = next_level
	var text = "LEVEL %d" % level
	%Readout.text = ""
	%Readout2.text = text
	print(text)
	
	dot_pos = screen_center
	# TODO: place target and prey

func _ready() -> void:
	setup_tilt_bridge()
	reset_screen()
	reset_level(1)
	
func get_direction_from_balance() -> Vector2:
	%Readout.text = "board: %d° %d%%" % [\
		rad_to_deg(Board.stick.angle()), \
		Board.stick.length() * speed / max_speed * 100 \
	]
	return Board.stick

var base := Vector2.ZERO  # the "level" position from the first reading
var has_base := false
func get_direction_from_accelerometer() -> Vector2:
	%Readout.text = "tilt: %s" % tilt.state
	if (tilt.gamma != null):
		%Readout.text += "\ngamma: %f\n beta: %f" % [tilt.gamma, tilt.beta]
		var reading := Vector2(tilt.gamma, tilt.beta)
		if (!has_base):  # save first reading as "level"
			has_base = true  # to reset, set has_base to false
			base = reading
		return (reading - base).normalized()
	return Vector2.ZERO

## Friction, the same at any frame rate. Multiply a speed by this every frame:
##   velocity *= Game.friction(delta)
## `keep` is how much survives one frame at 60 fps (1 - 1/60: lose ~1.7% a frame, so ~36%
## of the speed is left after a second, whatever the frame rate). It's raised to the power
## of "how many 60 fps frames was this frame" (delta * 60), so two 120 fps frames come out
## the same as one 60 fps frame. (The old version used 1 - delta as the per-frame number,
## which itself shrank at higher frame rates: at 120 fps things glided almost twice as far.)
## `glide` 0..1 blends toward no friction at all: the prey stops slowing down while scared.
const REFERENCE_FPS := 60.0
static func friction(delta: float, glide := 0.0, keep := 1.0 - 1.0 / REFERENCE_FPS) -> float:
	return pow(lerpf(keep, 1.0, glide), delta * REFERENCE_FPS)

var offset := Vector2.ZERO
var new_offset := Vector2.ZERO
var time_moving := 0.0
var max_time_moving := 2.0  # coast after key up
func get_direction_from_keyboard(delta) -> Vector2:
	%Readout.text = "desktop"
	offset *= friction(delta)
	if (Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") != Vector2.ZERO):  # arrows only: a second player's keys mustn't move this dot
		new_offset = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		offset = (offset + new_offset).clamp(Vector2.ZERO - screen_center, screen_center)
		time_moving = min(time_moving + delta, max_time_moving)
	else: 
		time_moving = max(time_moving - delta, 0)
		if !time_moving: offset = Vector2.ZERO
	#%Readout.text += "\ntime moving: %.2f" % time_moving
	return offset.normalized() * (time_moving/max_time_moving)

var velocity := Vector2.ZERO
var speed := 20.0
var max_speed := 100.0
var r := 24.0
var bounce := -0.5
func _process(delta) -> void:
	# save most of last frame's velocity: the usual friction, plus a little more the higher
	# `speed` is (1/speed per 60 fps frame), so a faster dot doesn't run away
	velocity *= friction(delta) * friction(delta, 0.0, 1.0 - 1.0/speed)
	
	# add player input to velocity
	# tilt only once it reads: a desktop browser has the bridge but never a reading
	var direction = get_direction_from_balance() if Board.active else \
		get_direction_from_accelerometer() if (tilt != null and tilt.gamma != null) else \
		get_direction_from_keyboard(delta)
	if (direction != Vector2.ZERO):
		#%Readout.text += "\ndirection: %d" % rad_to_deg(direction.angle())
		velocity += direction * speed * delta * REFERENCE_FPS
		velocity = velocity.limit_length(max_speed)
	
	# update dot position
	var size := screen_center * 2
	var next = dot_pos + velocity * delta
	if next.x < r or next.x > size.x - r: velocity.x *= bounce; offset.x *= bounce
	if next.y < r or next.y > size.y - r: velocity.y *= bounce; offset.y *= bounce
	dot_pos = (dot_pos + velocity * delta).clamp(Vector2(r, r), size - Vector2(r, r))
		
	$Prey.threat = dot_pos  # warn the prey
	
	queue_redraw()

static func warning_color(value: float) -> Color:
	if   (value > .99): return Color.RED
	elif (value > .90): return Color.ORANGE_RED
	elif (value > .75): return Color.ORANGE
	elif (value > .50): return Color.YELLOW
	elif (value > .25): return Color.YELLOW_GREEN
	elif (value > .10): return Color.GREEN
	elif (value > .01): return Color.CYAN
	else:               return Color.WHITE

static func speed_color(v:Vector2) -> Color:
	return Color.WHITE if v.length() < 1 else Color.GRAY

static func draw_velocity(v: Vector2, radius: float, max_length: float) -> Array[Vector2]:
	var on_circle = v.normalized() * radius
	var how_fast  = v.length() / max_length
	var start = on_circle*(1-how_fast)
	var end   = on_circle*(1+how_fast)
	return [start, end]

func _draw() -> void:
	draw_circle(dot_pos, r, speed_color(velocity))
	draw_circle(dot_pos, r, warning_color(time_moving / max_time_moving), false, 4)  # key held down
	
	if (velocity.length() >= 1):  # moving
		var v_line2 := draw_velocity(new_offset.normalized() * time_moving, r, max_time_moving)
		draw_line(dot_pos + v_line2[0], dot_pos + v_line2[1], Color.DIM_GRAY, 4)
		var v_line := draw_velocity(velocity, r, max_speed)
		draw_line(dot_pos + v_line[0], dot_pos + v_line[1], Color.BLACK, 4)

const collision_text := "SCARED IN!"
func _on_target_area_entered(area: Area2D) -> void:
	if area.is_in_group("prey"):
		%Readout2.text = collision_text
		print(collision_text)
		reset_level(level + 1)
