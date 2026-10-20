extends SceneTree
## Headless test for spirit.gd. From the ludum-dare-60 folder:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/test_spirit.gd
## A planchette with the same friction as the game, pushed by fake players. Deterministic.

const SpiritScript := preload("res://spirit.gd")
const DT := 1.0 / 60.0
var failures := 0


func _initialize() -> void:
	helping_player()
	stubborn_player()
	nobody_playing()
	two_players()
	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)


func check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("  %-52s %s  %s" % [name, "ok  " if ok else "FAIL", detail])


func friction(v: Vector2) -> Vector2:
	return v * pow(1.0 - 1.0 / 60.0, DT * 60.0)


## Runs `seconds` of play; `push(t, pos)` returns {who: impulse} for this frame.
func run(spirit: Node, start: Vector2, seconds: float, push: Callable) -> Dictionary:
	var pos := start
	var vel := Vector2.ZERO
	var howls := [0, 0]
	var arrived_at := -1.0
	var closest := INF
	spirit.howl.connect(func(near): howls[1 if near else 0] += 1)
	for i in int(seconds / DT):
		var t := i * DT
		vel = friction(vel)
		# once the word is read there's nothing to push toward (the next card would start here)
		var players: Dictionary = {} if spirit.target == Vector2.INF else push.call(t, pos)
		for who in players:
			spirit.record(who, players[who])
			vel += players[who]
		vel += spirit.impulse(pos, vel, DT)
		vel = vel.limit_length(100.0)
		pos += vel * DT
		if spirit.target != Vector2.INF:
			closest = minf(closest, pos.distance_to(spirit.target))
			if pos.distance_to(spirit.target) < spirit.settle_radius and vel.length() < 25.0:
				arrived_at = t           # the word is read: in the game, the card changes here
				spirit.target = Vector2.INF
	return {"pos": pos, "howls": howls, "arrived": arrived_at, "closest": closest}


func new_spirit() -> Node:
	var s: Node = SpiritScript.new()
	s.target = Vector2(400, 0)
	return s


## A player who pushes toward the word, a bit clumsily.
func helping_player() -> void:
	print("one player, pushing toward the word")
	var s := new_spirit()
	var r := run(s, Vector2.ZERO, 30.0, func(t, pos):
		var dir: Vector2 = (s.target - pos).normalized().rotated(0.6 * sin(t * 1.7))
		return {"p1": dir * 1.2 if fmod(t, 3.0) < 2.0 else Vector2.ZERO})
	check("reaches the word", r.arrived >= 0.0, "after %.1f s (closest %.0f px)" % [r.arrived, r.closest])
	check("spirit's share stays under its cap", s.share("spirit") <= s.share_cap + 0.01, "spirit %.1f%%" % (s.share("spirit") * 100))
	check("verdict: mostly you", s.verdict() == "it was mostly you.", s.verdict())


## A player who pushes the planchette away from the word the whole time.
func stubborn_player() -> void:
	print("one player, pushing away from the word")
	var s := new_spirit()
	var r := run(s, Vector2(200, 0), 30.0, func(t, pos):
		return {"p1": (pos - s.target).normalized() * 0.8})
	check("spirit's share stays under its cap", s.share("spirit") <= s.share_cap + 0.01, "spirit %.1f%%" % (s.share("spirit") * 100))
	check("spirit never took over", not s.in_control, "")


## Nobody touches it: the spirit finishes alone, and says so.
func nobody_playing() -> void:
	print("nobody playing")
	var s := new_spirit()
	var r := run(s, Vector2.ZERO, 30.0, func(t, pos): return {})
	check("took over and reached the word", r.arrived > 0.0, "after %.1f s" % r.arrived)
	check("verdict: mostly me", s.verdict().begins_with("it was mostly me"), s.verdict())
	check("howls, but not constantly", r.howls[0] + r.howls[1] >= 1 and r.howls[0] + r.howls[1] <= 3, "far %d, near %d" % r.howls)


## Two players both aiming for the word, each wrong in a different way: both counted, spirit
## still small. (Two players pushing against each other on purpose can stall it, by design:
## the spirit is too weak to overrule a person.)
func two_players() -> void:
	print("two players")
	var s := new_spirit()
	var r := run(s, Vector2.ZERO, 40.0, func(t, pos):
		return {"p1": (s.target - pos).normalized().rotated(0.7 * cos(t * 1.3)) * 0.9,
			"p2": (s.target - pos).normalized().rotated(1.1 * sin(t * 0.9)) * 0.9})
	var who := []
	for pair in s.shares():
		who.append("%s %.0f%%" % [pair[0], pair[1] * 100])
	check("both players counted, spirit under its cap", s.share("p1") > 0.2 and s.share("p2") > 0.2 and s.share("spirit") <= s.share_cap + 0.01, ", ".join(who))
	check("reaches the word", r.arrived >= 0.0, "after %.1f s (closest %.0f px)" % [r.arrived, r.closest])
