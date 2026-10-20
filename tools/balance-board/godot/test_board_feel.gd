extends SceneTree
## Replay test for Board.Feel: no board, no server. Run from the ludum-dare-60 folder:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path tools/balance-board/godot --script res://test_board_feel.gd
## Prints a score per scenario and exits 1 if any fails. Deterministic (seeded noise).

const BoardInput := preload("res://board_input.gd")
const DT := 1.0 / 30.0
const KG := 60.0     # the recording stores weight as a fraction; any plausible weight works

var failures := 0


func _initialize() -> void:
	recorded_session()
	off_centre_sway()
	stance_creeps()
	held_lean()
	stepping_on()
	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)


func check(name: String, value: float, at_least: float) -> void:
	var ok := value >= at_least
	if not ok:
		failures += 1
	print("  %-46s %5.1f%%  (need %.0f%%)  %s" % [name, value * 100, at_least * 100, "ok" if ok else "FAIL"])


func label(d: Vector2) -> String:
	if d == Vector2.ZERO: return "still"
	if d.x > 0.7: return "right"
	if d.x < -0.7: return "left"
	if d.y > 0.7: return "heels"
	if d.y < -0.7: return "toes"
	return "diagonal"


## The 2026-10-16 session: step on, stand, right, left, heels, toes, step off.
## Windows are seconds since stepping on, read off the recording; transitions are skipped.
func recorded_session() -> void:
	print("recorded session (recordings/2026-10-16-lean-test.txt)")
	var f := FileAccess.open("res://../recordings/2026-10-16-lean-test.txt", FileAccess.READ)
	var feel := BoardInput.Feel.new()
	var expect := [[1.2, 2.4, "still"], [3.0, 4.9, "right"], [6.6, 8.8, "left"],
		[10.6, 12.3, "heels"], [13.1, 16.3, "toes"]]
	var hits := {}
	var counts := {}
	var t_on := -1.0
	var t := 0.0
	var on_count := 0
	var timeline := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var v := line.split_floats(" ", false)
		feel.update(Vector2(v[0], v[1]), v[2] * KG, DT)
		t += DT
		if feel.on_board and t_on < 0.0:
			t_on = t
		if t_on < 0.0:
			continue
		var s := t - t_on
		if on_count % 15 == 0:
			timeline += "%s " % label(feel.direction).substr(0, 1)
		on_count += 1
		for e in expect:
			if s >= e[0] and s <= e[1]:
				counts[e[2]] = counts.get(e[2], 0) + 1
				if label(feel.direction) == e[2]:
					hits[e[2]] = hits.get(e[2], 0) + 1
	print("  every 0.5 s: " + timeline)
	for e in expect:
		check("%s from %.1f to %.1f s" % [e[2], e[0], e[1]], float(hits.get(e[2], 0)) / counts[e[2]], 0.9)


func sway(rng: RandomNumberGenerator, t: float, centre: Vector2) -> Vector2:
	return centre + Vector2(0.05 * sin(TAU * 0.3 * t), 0.03 * sin(TAU * 0.23 * t + 1.0)) \
		+ Vector2(rng.randfn(0.0, 0.02), rng.randfn(0.0, 0.02))


## Standing off-centre and swaying like a person does: should never move.
func off_centre_sway() -> void:
	print("standing off-centre, swaying, 20 s")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var feel := BoardInput.Feel.new()
	var still := 0
	var n := 0
	for i in 600:
		var t := i * DT
		feel.update(sway(rng, t, Vector2(0.12, 0.08)), KG + rng.randfn(0.0, 0.3), DT)
		if t > 1.0:
			n += 1
			still += int(feel.direction == Vector2.ZERO)
	check("still the whole time", float(still) / n, 0.99)


## Feet slowly shift to a new resting spot over 15 s: "level" should follow.
func stance_creeps() -> void:
	print("stance creeps 0.2 sideways over 15 s")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var feel := BoardInput.Feel.new()
	var still := 0
	var n := 0
	for i in 600:
		var t := i * DT
		var centre := Vector2(0.0, 0.0).lerp(Vector2(0.2, 0.1), clampf((t - 2.0) / 15.0, 0.0, 1.0))
		feel.update(sway(rng, t, centre), KG, DT)
		if t > 1.0:
			n += 1
			still += int(feel.direction == Vector2.ZERO)
	check("still the whole time", float(still) / n, 0.97)


## Stand, then lean right and hold it for 8 s, then come back.
func held_lean() -> void:
	print("lean right and hold for 8 s")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var feel := BoardInput.Feel.new()
	var held := 0
	var held_n := 0
	var back := 0
	var back_n := 0
	for i in 450:
		var t := i * DT
		var lean := 0.3 if t >= 3.0 and t < 11.0 else 0.0
		feel.update(sway(rng, t, Vector2(0.1 + lean, 0.05)), KG, DT)
		if t >= 3.4 and t < 11.0:
			held_n += 1
			held += int(label(feel.direction) == "right")
		if t >= 11.6:
			back_n += 1
			back += int(feel.direction == Vector2.ZERO)
	check("moving right while held (after 0.4 s)", float(held) / held_n, 0.98)
	check("still again after coming back (0.6 s)", float(back) / back_n, 0.98)


## The first half second of stepping on is a mess: no direction until settled.
func stepping_on() -> void:
	print("stepping on")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var feel := BoardInput.Feel.new()
	var quiet := 0
	var n := 0
	for i in 60:
		var t := i * DT
		var w := KG * clampf(t / 0.5, 0.0, 1.0) + (rng.randfn(0.0, 8.0) if t < 0.6 else 0.0)
		var lean := Vector2(-0.4, 0.4).lerp(Vector2(0.1, 0.05), clampf(t / 0.6, 0.0, 1.0))
		feel.update(lean + Vector2(rng.randfn(0.0, 0.05), rng.randfn(0.0, 0.05)), w, DT)
		if t < 1.0:
			n += 1
			quiet += int(feel.direction == Vector2.ZERO)
	check("no direction in the first second", float(quiet) / n, 1.0)
