extends Node
class_name Spirit
## The third player: the time machine's hand on the planchette.
##
## It never moves the planchette by itself while you're playing: it adds a small push toward
## the word it wants (the current target), on top of the pushes your hands make, and it keeps
## count of who pushed how much. If everyone lets go, it takes over and finishes the sentence
## alone, and the count shows that too. The ending reads the count (see `verdict()`).
##
## Use, from whatever moves the planchette, every physics frame:
##   spirit.target = <where the current word is, in the same space as the planchette>
##   spirit.record("p1", impulse)            # each player's push this frame (a velocity change)
##   velocity += spirit.impulse(position, velocity, delta)   # the spirit's push, recorded too
## Listen to `howl` for the coyotes, and to `took_over` / `gave_back` if you want to react.

signal howl(near: bool)       ## the spirit pushed hard: far coyotes, or near ones if it's strong
signal took_over              ## nobody has pushed for a while: the spirit moves alone now
signal gave_back              ## somebody pushed again

## How much of all the pushing the spirit allows itself while people are playing (0..1).
## It eases off as its share approaches this, so "it was mostly you" stays true by design.
@export var share_cap := 0.12
## Its guiding pull, in velocity per second, when it's well under its cap.
@export var guide := 40.0
## Seconds without any player push before it takes over, and its pull once it has.
@export var idle_before_takeover := 5.0
@export var takeover_pull := 70.0
## Close to the word, it settles the planchette onto it like a damped spring: a pull toward the
## exact spot (per second squared, per pixel) and damping (per second). Without the pull it
## would stop wherever it entered the zone, which can be short of where the word is read.
@export var settle_radius := 40.0
@export var settle_spring := 3.0
@export var settle_damping := 3.5
## Coyotes: at most one howl per this many seconds, and how strong a push earns one.
@export var howl_every := 18.0

var target := Vector2.INF        ## where the word is; INF = nothing to say right now
var pushed := {}                 ## who -> total push (sum of impulse lengths)
var in_control := false          ## true while it has taken over

var _idle := 0.0
var _since_howl := 999.0
var _strain := 0.0               ## how hard it has been pushing lately (0..1), for the howls


## A player's push this frame. `who` is any name: "p1", "p2", "board", "phone"...
## `active` false means their hand is resting, not moving: the push still counts toward who
## moved the planchette, but it doesn't stop the spirit from deciding they've let go.
func record(who: String, impulse: Vector2, active := true) -> void:
	var amount := impulse.length()
	if amount <= 0.0:
		return
	pushed[who] = pushed.get(who, 0.0) + amount
	if not active:
		return
	_idle = 0.0
	if in_control:
		in_control = false
		gave_back.emit()


## The spirit's own push this frame (add it to the planchette's velocity). Recorded as "spirit".
func impulse(position: Vector2, velocity: Vector2, delta: float) -> Vector2:
	_idle += delta
	_since_howl += delta
	if target == Vector2.INF:
		_strain = move_toward(_strain, 0.0, delta)
		return Vector2.ZERO

	if not in_control and _idle > idle_before_takeover:
		in_control = true
		took_over.emit()

	var to_word := target - position
	# while people are playing, it holds back more and more as its share nears the cap
	var room := 1.0 if in_control else clampf(1.0 - share("spirit") / share_cap, 0.0, 1.0)
	var push := Vector2.ZERO
	if to_word.length() < settle_radius:
		# almost there: settle the planchette onto the word so it can be read
		push = (to_word * settle_spring - velocity * settle_damping) * delta * room
	elif in_control:
		push = to_word.normalized() * takeover_pull * delta
	else:
		push = to_word.normalized() * guide * room * delta

	pushed["spirit"] = pushed.get("spirit", 0.0) + push.length()
	_strain = lerpf(_strain, clampf(push.length() / (takeover_pull * delta), 0.0, 1.0), minf(delta * 2.0, 1.0))
	if _strain > 0.5 and _since_howl > howl_every:
		_since_howl = 0.0
		howl.emit(_strain > 0.85)
	return push


## Share of all pushing done by `who` (0..1).
func share(who: String) -> float:
	var total := 0.0
	for amount in pushed.values():
		total += amount
	return pushed.get(who, 0.0) / total if total > 0.0 else 0.0


## Everyone's share, largest first: [[who, share], ...]
func shares() -> Array:
	var out := []
	for who in pushed:
		out.append([who, share(who)])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out


## The last line of the game, read from the count.
func verdict() -> String:
	return "it was mostly you." if share("spirit") < 0.5 else "it was mostly me. you let go."


## Start a new session: forget the count.
func reset() -> void:
	pushed.clear()
	in_control = false
	_idle = 0.0
	_strain = 0.0
	target = Vector2.INF
