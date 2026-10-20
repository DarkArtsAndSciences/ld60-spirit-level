extends Node2D
## The session: the rules, the coins, the board, the eight cards, the secret, goodbye, the
## transcript.
##
## A drop-in around Dark Arts and Sciences' game. It instances main.tscn as it is: prey.gd is still the pointer
## (the hand that points at the words), and the controls are main.gd's own functions: her arrow
## keys (whose time_moving, ticking down after you let go of the keys, is how the game knows
## your hands are still on), her tilt and the Balance Board. Each player picks their own
## controller, so the séance switches off main.gd's _process (which reads one controller for
## one dot) and moves both players' coins itself, with main.gd's numbers. Player 2 pushes the
## pointer by the same rule prey.gd uses for player 1, and player three (spirit.gd) adds its
## own push. Everything it shows comes from message/message_data.gd.
##
## How it goes (Dark Arts and Sciences' design):
##   the rules.
##   the coins: each player picks a controller by using it, then rolls their coin into the 1P
##     or 2P slot: the first level, alone, to show you've got the controls. Nothing starts until
##     both coins are in (rule 1). Your coin is your hand on the board from then on.
##   "is anyone there?": push the pointer onto YES. Player three shows up: you can see it push.
##   "who are you?": player three takes the pointer and spells its answer, a letter at a time,
##     with only the letters on the board. Keep your hands on and be still. Let go (the keys'
##     time_moving runs out, you step off the board, you let go of the mouse) and it ends
##     there (rule 2).
##   the cards: push the pointer onto the word in each picture. Player three helps, a little,
##     and never plays by itself.
##   the secret, if you both did your share.
##   goodbye: it spells that itself too. Hands on until it's done.
##   the transcript.
##
## To play it: make seance.tscn the main scene (Project > Project Settings > Application >
## Run > Main Scene), or open it and press Cmd+R (Run Current Scene).
## Testing: `-- --bot` two bot players play it through, `-- --letgo` the second bot lets go
## while it spells, `-- --idle` two bots put their coins in and then do nothing (it should wait
## for them, not play itself), `-- --alone` one bot (it should never start), `-- --log` prints
## each step with the time, `-- --quit-at-end` quits after the transcript.

const TITLE := "Spirit Level"
const RULES := "1. never play alone.\n\n2. keep your hands on until it says goodbye."
const ANSWER := "NOBODY"        # who are you? It only has the letters on the board to say it with
const MessageData := preload("res://message/message_data.gd")
const SpiritScript := preload("res://spirit.gd")

const BG := Color(0.16, 0.11, 0.14)
const PAPER := Color(0.94, 0.92, 0.86)
const DIM := Color(0.94, 0.92, 0.86, 0.55)
const AMBER := Color(1.0, 0.78, 0.45)
const GHOST := Color(0.7, 0.82, 1.0)
const FAR := Vector2(-100000, -100000)   # where a threat is when there isn't one
const READ_RADIUS := 30.0       # how close the fingertip must be to the word (at card scale 1)
const READ_HOLD := 0.2          # for this long in all: a touch, like main.gd's Target, not a stop
                                # (a scared pointer glides; asking it to rest fought prey.gd)
const HINT_AFTER := 8.0         # seconds on "is anyone there?" before the hint shows
const PAUSE_AFTER_WORD := 3.2   # seconds between a word being read and the next card
const SECRET_SHARE := 0.25      # each player's part of the two players' pushing, for the secret
const SPEED := 20.0             # the coins move like main.gd's dot: its speed, max_speed, r
const MAX_SPEED := 100.0
const COIN_R := 26.0
const SLOT_MOUTH := 34.0        # how close a coin must roll to a slot to drop in
const HANDS_ON := 0.25          # everyone's grip must be this much before it starts to spell
const SPELL_SPRING := 7.0       # player three's hand, when it has the pointer
const SPELL_DAMPING := 5.0
const SPELL_SPEED := 240.0
const SPELL_REST := 0.5         # it rests on each letter this long
const SPARK_TIME := 0.8         # a light flies from the target to the caption before the words
const WORD_EVERY := 0.55        # a card's hidden words light up one at a time, this far apart
const CAPTION_COLOR := "#f0eadc"
const HIDDEN_COLOR := "#ffc773"

enum Step { TITLE, COINS, ANYONE, WHO, CARD, READ, FINALE, GOODBYE, TRANSCRIPT }


## main.gd's arrow keys (get_direction_from_keyboard) for the other set of keys: the same
## offset, the same time_moving.
class Keys:
	var actions: Array = []
	var offset := Vector2.ZERO
	var new_offset := Vector2.ZERO
	var time_moving := 0.0
	var max_time_moving := 2.0

	func direction(delta: float, limit: Vector2) -> Vector2:
		offset *= Game.friction(delta)
		var held := Input.get_vector(actions[0], actions[1], actions[2], actions[3])
		if held != Vector2.ZERO:
			new_offset = held
			offset = (offset + new_offset).clamp(-limit, limit)
			time_moving = minf(time_moving + delta, max_time_moving)
		else:
			time_moving = maxf(time_moving - delta, 0.0)
			if time_moving == 0.0:
				offset = Vector2.ZERO
		return offset.normalized() * (time_moving / max_time_moving)


## A player: their controller, their coin (their hand on the board) and their grip.
class Hand:
	var device := ""            # "board", "tilt", "arrows", "wasd", "mouse" or "bot"
	var label := ""             # what the slot calls them: "the arrow keys", "the board"...
	var slot := 0               # 1 or 2 once their coin is in
	var coin: Texture2D
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var dir := Vector2.ZERO     # this frame's push from the controller, 0..1 long
	var grip := 0.0             # hands on, 0..1. It runs down over 2 s once they let go
	var slipping := false       # their grip went down this frame
	var fear := 0.0             # how scared the pointer is of this hand (2P's; prey.gd keeps 1P's)
	var spin := 0.0             # the coin rolls as it moves
	var inserted := -1.0        # going into the slot, 0..1; -1 before
	var tint := Color.WHITE
	var keys: Keys


var data: Dictionary = MessageData.DATA
var step := Step.TITLE
var step_time := 0.0
var card_index := -1            # 0..7 during the cards; 8 = the secret
var hour := 7
var shown_hour := 0
var told: Array[String] = []    # the transcript, line by line
var reading := 0.0
var target := Vector2.INF       # where the current word is, on screen

var game: Node2D                # main.tscn
var prey: Area2D                # the pointer's body (prey.gd)
var spirit: Node                # spirit.gd: player three
var hands: Array[Hand] = []
var ghost := Vector2.ZERO       # player three's push lately, for its hand
var fingertip := Vector2.ZERO
var tilt_angle := 0.0           # the pointer leans a little as it moves

# the caption: the card's words are hidden in it, and light up one at a time once it's read
var caption := RichTextLabel.new()
var caption_parts: Array = []   # [text, hidden word index or -1]
var hidden_count := 0
var revealed := 0
var reveal_to := 0
var card_centre := Vector2.ZERO
var card_size := Vector2.ZERO   # on screen
var hit_glow := 0.0             # the target lights up when it's read
var finale := 0.0               # the secret's ending, in seconds

# spelling: player three has the pointer
var spelling := ""
var spell_i := 0
var spell_at: Sprite2D = null   # the letter it's on its way to
var spell_last: Sprite2D = null
var spell_rest := 0.0
var listening := false          # it has the pointer: hands on, be still
var let_go := ""                # who let go, if anyone did
var lit := {}                   # letter sprite -> how lit up it still is, 0..1

# controllers
var mouse_drag := 0.0
var mouse_push := Vector2.ZERO
var mouse_dir := Vector2.ZERO
var tilt_first := Vector2.INF
var both_in := 0.0

var card_sprite := Sprite2D.new()
var board := Node2D.new()
var clock_sprite := Sprite2D.new()
var letters := {}               # "YES"/"NO"/"GOODBYE" -> Node2D of letter sprites
var planchette := Sprite2D.new()
var marks := Node2D.new()       # the slots and the coins, under the pointer
var over := Node2D.new()        # player three's hand, over the pointer
var hour_sprite := Sprite2D.new()
var title_sprite := Sprite2D.new()
var ui := CanvasLayer.new()
var top_label := Label.new()
var words_label := Label.new()
var hint_label := Label.new()
var big_label := Label.new()
var end_sprite := Sprite2D.new()
var sounds := {}                # name -> AudioStreamPlayer
var heading := 0.0              # where the pointer's finger points
var font_px := 20

# testing
var args := OS.get_cmdline_user_args()
var bots := 1 if "--alone" in args else 2 if ("--bot" in args or "--bot2" in args or "--letgo" in args or "--idle" in args) else 0
var bots_push := "--bot" in args or "--bot2" in args or "--letgo" in args
var logging := "--log" in args or bots > 0
var clock := 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(BG)
	process_priority = 10              # after prey.gd
	process_physics_priority = 10      # after prey.gd has moved the pointer

	game = preload("res://main.tscn").instantiate()
	add_child(game)
	game.visible = false               # its dots and readouts are for debugging
	game.set_process(false)            # the séance moves the players (see the top)
	prey = game.get_node("Prey")
	prey.threat = FAR
	game.get_node("Target").position = FAR

	spirit = SpiritScript.new()
	add_child(spirit)
	spirit.idle_before_takeover = INF  # it never plays by itself: it waits for you
	spirit.howl.connect(_on_howl)

	for name in ["left", "right", "up", "down"]:
		var action: String = "p2_" + name
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = {"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S}[name]
			InputMap.action_add_event(action, key)

	for node in [card_sprite, board, marks, planchette, over, hour_sprite, title_sprite, end_sprite]:
		add_child(node)
	card_sprite.centered = true
	board.add_child(clock_sprite)
	clock_sprite.texture = load(data.board.clock.image)
	for word in ["YES", "NO", "GOODBYE"]:
		var row := Node2D.new()
		for i in word.length():
			var s := Sprite2D.new()
			s.texture = load(data.letters[word[i]])
			s.set_meta("letter", word[i])
			row.add_child(s)
		board.add_child(row)
		letters[word] = row
	planchette.texture = load(data.planchette.image)
	planchette.centered = false
	fingertip = Vector2(data.planchette.fingertip[0], data.planchette.fingertip[1])
	planchette.offset = -fingertip
	marks.draw.connect(_draw_marks)
	over.draw.connect(_draw_ghost)
	title_sprite.texture = load(data.board.rules.image)
	end_sprite.texture = load(data.board.the_end.image)
	for node in [card_sprite, board, end_sprite, title_sprite, hour_sprite, planchette]:
		node.visible = false              # each step shows what it needs

	add_child(ui)
	for label in [top_label, words_label, hint_label, big_label]:
		ui.add_child(label)
		label.add_theme_color_override("font_color", PAPER)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui.add_child(caption)
	caption.bbcode_enabled = true
	caption.scroll_active = false
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_color_override("default_color", PAPER)
	hint_label.add_theme_color_override("font_color", DIM)

	for name in data.sounds:
		var player := AudioStreamPlayer.new()
		player.stream = load(data.sounds[name])
		add_child(player)
		sounds[name] = player
	for name in ["night_insects", "dusk", "drive_spinning"]:
		sounds[name].stream.loop = true
	_volumes({"night_insects": -16, "dusk": -14, "drive_spinning": -14, "drive_spin_up": -6,
		"drive_eject": -4, "tray_close": -6, "siren_and_coyotes": -4, "coyotes_far": -3,
		"coyotes_near": -3, "lone_coyote": -3, "two_howls": -3})

	_go(Step.TITLE)


func _volumes(levels: Dictionary) -> void:
	for name in levels:
		if name in sounds:
			sounds[name].volume_db = levels[name]


# ---- the steps ------------------------------------------------------------------------------

func _go(next: Step) -> void:
	step = next
	step_time = 0.0
	reading = 0.0
	big_label.text = ""
	if logging:
		print("%7.1f  %s%s" % [clock, Step.keys()[step], "" if step != Step.CARD else " %d" % (card_index + 1)])
	match step:
		Step.TITLE:
			spirit.target = Vector2.INF
			hint_label.text = "press a key, or tap, to sit down"
			title_sprite.visible = true
			if bots > 0:
				_go(Step.COINS)
		Step.COINS:
			title_sprite.visible = false
			top_label.text = "INSERT COIN"
			sounds.dusk.play()
			for i in bots:
				_join("bot", ["the first bot", "the second bot"][i])
		Step.ANYONE:
			board.visible = true
			_place_pointer(_view().size * Vector2(0.5, 0.42))
			for h in hands:
				h.pos = _view().size * Vector2(0.3 if h.slot == 1 else 0.7, 0.9)   # hands start off the board
				h.vel = Vector2.ZERO
			top_label.text = "they asked:  is anyone there?"
			hint_label.text = ""
			sounds.siren_and_coyotes.play()
		Step.WHO:
			told.append_array(["they asked:  is anyone there?", "it said:  YES", "they asked:  who are you?", "it said:  "])
			top_label.text = "they asked:  who are you?"
			_spell(ANSWER)
		Step.CARD:
			board.visible = false
			var card: Dictionary = data.cards[card_index] if card_index < data.cards.size() else data.secret
			card_sprite.texture = load(card.image)
			card_sprite.visible = true
			card_sprite.modulate = Color.WHITE
			words_label.text = ""
			top_label.text = ""
			hint_label.text = ""
			_set_caption(card.caption)
			_layout()
			# the pointer starts outside the frame, beside the caption: see the photo first
			# (in the middle of the column, low enough to leave room to get a coin round it)
			_place_pointer(Vector2(card_centre.x + card_size.x * 0.5 + (_view().size.x - card_centre.x - card_size.x * 0.5) * 0.5, _view().size.y * 0.7))
			sounds.dusk.stop()
			if not sounds.night_insects.playing:
				sounds.night_insects.play()
			sounds.drive_spin_up.play()
			sounds.drive_spinning.play(randf() * 20.0)
		Step.READ:
			spirit.target = Vector2.INF
			sounds.drive_spinning.stop()
			sounds.drive_eject.play()
			var card: Dictionary = data.cards[card_index] if card_index < data.cards.size() else data.secret
			told.append(card.words)
			hit_glow = 1.0
			# the secret keeps its last two words ("you weren't") for its ending
			reveal_to = hidden_count - 2 if card_index >= data.cards.size() else hidden_count
			if card.has("hour"):
				hour = card.hour
		Step.FINALE:
			finale = 0.0
			listening = false
			hint_label.text = "hands on.  be still."
		Step.GOODBYE:
			caption.visible = false
			card_sprite.visible = false
			board.visible = true
			words_label.text = ""
			top_label.text = ""
			told.append("")
			sounds.night_insects.stop()
			sounds.dusk.play()
			_spell("GOODBYE")
		Step.TRANSCRIPT:
			listening = false
			caption.visible = false
			prey.speed = 100.0
			for node in [board, card_sprite, planchette, hour_sprite]:
				node.visible = false
			top_label.text = ""
			words_label.text = ""
			big_label.text = _transcript()
			hint_label.text = "press a key, or tap, to sit again"
			end_sprite.visible = true
			for name in ["dusk", "night_insects", "drive_spinning"]:
				sounds[name].stop()
			# let go: the drive spins down. Held on: the tray closes.
			(sounds.drive_eject if let_go != "" else sounds.tray_close).play()
			if logging:
				print(big_label.text)


func _process(delta: float) -> void:
	clock += delta
	step_time += delta
	_layout()
	_controllers(delta)
	if bots > 0:
		_bot(delta)
	if "--keys" in args:
		_keys_test()
	_move_hands(delta)
	var p1 := _in_slot(1)
	prey.threat = p1.pos if p1 != null and _hands_push() else FAR
	match step:
		Step.COINS:
			_coins(delta)
		Step.ANYONE:
			# a few seconds to work it out alone, then a hint
			if step_time > HINT_AFTER and hint_label.text == "":
				hint_label.text = "push the pointer onto YES.  it runs from your coin."
			if _read(delta):
				hint_label.text = ""
				_go(Step.WHO)
		Step.WHO:
			if _spelling(delta):
				card_index = 0
				_go(Step.CARD)
		Step.CARD:
			if _read(delta):
				_go(Step.READ)
		Step.READ:
			# the photo dims and a light flies to the caption, so your eye goes to the words
			card_sprite.modulate = Color.WHITE.lerp(Color(0.55, 0.55, 0.55), clampf(step_time / SPARK_TIME, 0.0, 1.0))
			if revealed < reveal_to and step_time > SPARK_TIME + WORD_EVERY * revealed:
				revealed += 1
				_show_caption()
			if card_index >= data.cards.size() and step_time > SPARK_TIME + WORD_EVERY * reveal_to + 1.0:
				_go(Step.FINALE)
			elif step_time > SPARK_TIME + WORD_EVERY * reveal_to + 2.4:
				card_index += 1
				if card_index < data.cards.size():
					_go(Step.CARD)
				elif card_index == data.cards.size() and _two_players():
					_go(Step.CARD)            # the secret card
				else:
					_go(Step.GOODBYE)
		Step.FINALE:
			_finale(delta)
		Step.GOODBYE:
			if _spelling(delta):
				_go(Step.TRANSCRIPT)
		Step.TRANSCRIPT:
			if "--quit-at-end" in args and step_time > 1.0:
				get_tree().quit(0)
	for s in lit:
		lit[s] = maxf(lit[s] - delta * 0.5, 0.0)
	hit_glow = maxf(hit_glow - delta * 0.5, 0.0)
	_update_planchette(delta)
	marks.queue_redraw()
	over.queue_redraw()
	if "--trace" in args and int(clock * 2.0) != int((clock - delta) * 2.0):
		var where := []
		for h in hands:
			where.append("%s %s grip %.2f" % [h.label, h.pos.round(), h.grip])
		print("  t %.1f %s pointer %s v %.0f fear %.2f target %s reading %.2f listening %s spell %d  %s" % [
			clock, Step.keys()[step], prey.position.round(), prey.velocity.length(), prey.fear,
			target.round() if target != Vector2.INF else target, reading, listening, spell_i, " | ".join(where)])


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if step == Step.TITLE and pressed:
		_go(Step.COINS)
	elif step == Step.TRANSCRIPT and pressed and step_time > 2.0:
		get_tree().reload_current_scene()
	# the mouse (or a finger): drag the way you want your coin to go
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		mouse_drag += event.relative.length()
		mouse_push += event.relative
		mouse_dir = event.relative.normalized() * clampf(event.relative.length() / 8.0, 0.0, 1.0)
		# the mouse joins here, not in _controllers: in a browser a quick drag's press, motion
		# and release can all arrive in one frame, and the release resets the drag
		if step == Step.COINS and mouse_drag > 30.0 and hands.size() < 2 and not _has("mouse"):
			_join("mouse", "a finger" if DisplayServer.is_touchscreen_available() else "the mouse")
	elif event is InputEventMouseButton and not event.pressed:
		mouse_drag = 0.0


func _physics_process(delta: float) -> void:
	var push := Vector2.ZERO          # player three's, this frame
	if _hands_push():
		# player 1's push this frame, exactly as prey.gd applied it
		var p1 := _in_slot(1)
		if p1 != null and prey.fear > 0.0 and prey.position != prey.threat:
			_record("1P", (prey.position - prey.threat).normalized() * prey.fear)
		# player 2's push, by the same rule
		var p2 := _in_slot(2)
		if p2 != null:
			var away := prey.position - p2.pos
			var d := away.length()
			if d < prey.scare_radius:
				p2.fear += sqrt((prey.scare_radius - d) / prey.scare_radius) * delta
			else:
				p2.fear *= Game.friction(delta)
			if p2.fear > 0.0 and d > 0.001:
				var p2_push := away.normalized() * p2.fear
				prey.velocity += p2_push
				_record("2P", p2_push)
		push = spirit.impulse(prey.position, prey.velocity, delta)
	elif listening and spell_at != null:
		# player three has it: a damped spring onto the letter
		push = ((spell_at.global_position - prey.position) * SPELL_SPRING - prey.velocity * SPELL_DAMPING) * delta
	elif listening and step == Step.FINALE:
		# it holds the pointer where the fingers meet: nearly still, a tremor so you can tell
		push = ((target - prey.position) * SPELL_SPRING - prey.velocity * SPELL_DAMPING) * delta \
			+ Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 40.0 * delta
	prey.velocity += push
	if delta > 0.0:
		ghost = ghost.lerp(push / delta, minf(delta * 5.0, 1.0))


## While the players' hands push the pointer (the rest of the time, they're in the slots, or
## player three has it).
func _hands_push() -> bool:
	return step in [Step.ANYONE, Step.CARD, Step.READ]


func _record(who: String, push: Vector2) -> void:
	if push.length() > 0.02:      # a fading fear isn't a hand on the pointer
		spirit.record(who, push)


func _two_players() -> bool:
	var a: float = spirit.pushed.get("1P", 0.0)
	var b: float = spirit.pushed.get("2P", 0.0)
	return a + b > 0.0 and minf(a, b) / (a + b) >= SECRET_SHARE


# ---- the controllers and the coins -----------------------------------------------------------

## Reads each player's controller: the push (dir) and the grip. A controller joins by being
## used, while there's a coin left to give it.
func _controllers(delta: float) -> void:
	if step == Step.COINS and hands.size() < 2:
		if Board.active and not _has("board"):
			_join("board", "the board")
		elif Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") != Vector2.ZERO and not _has("arrows"):
			_join("arrows", "the arrow keys")
		elif Input.get_vector("p2_left", "p2_right", "p2_up", "p2_down") != Vector2.ZERO and not _has("wasd"):
			_join("wasd", "WASD")
		elif _tilted() and not _has("tilt"):
			_join("tilt", "the phone")
	var mouse_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	for h in hands:
		var was := h.grip
		match h.device:
			"board":
				h.dir = game.get_direction_from_balance()
				h.grip = move_toward(h.grip, 1.0 if Board.active else 0.0, delta * (1.0 if Board.active else 0.5))
			"tilt":
				h.dir = game.get_direction_from_accelerometer()
				h.grip = 1.0      # a phone can't tell when it's been put down
			"arrows":
				h.dir = game.get_direction_from_keyboard(delta)
				h.grip = game.time_moving / game.max_time_moving   # Dark Arts and Sciences': keys held, ticking down after
			"wasd":
				h.dir = h.keys.direction(delta, _view().size * 0.5)
				h.grip = h.keys.time_moving / h.keys.max_time_moving
			"mouse":
				h.dir = mouse_dir
				h.grip = move_toward(h.grip, 1.0 if mouse_down else 0.0, delta * (1.0 if mouse_down else 0.5))
		h.slipping = h.grip < was
	mouse_dir = mouse_dir.move_toward(Vector2.ZERO, delta * 3.0)


func _join(device: String, label: String) -> void:
	var h := Hand.new()
	h.device = device
	h.label = label
	h.coin = load(data.coins["first" if hands.is_empty() else "second"])
	h.tint = Color.WHITE if hands.is_empty() else Color(1.0, 0.82, 0.5)   # the ECU in brass
	h.pos = _view().size * Vector2(0.34 if hands.is_empty() else 0.66, 0.8)
	if device == "wasd":
		h.keys = Keys.new()
		h.keys.actions = ["p2_left", "p2_right", "p2_up", "p2_down"]
	if device == "tilt":
		game.base = tilt_first          # level is how they held it when the game first saw it
		game.has_base = true
	if device == "bot":
		h.grip = 1.0
	hands.append(h)
	if logging:
		print("%7.1f  picked: %s" % [clock, label])


func _has(device: String) -> bool:
	for h in hands:
		if h.device == device:
			return true
	return false


func _in_slot(n: int) -> Hand:
	for h in hands:
		if h.slot == n:
			return h
	return null


func _tilt_available() -> bool:
	return game.tilt != null and (game.tilt.gamma != null or str(game.tilt.state).begins_with("tap"))


func _tilted() -> bool:
	if game.tilt == null or game.tilt.gamma == null:
		return false
	var reading_now := Vector2(float(game.tilt.gamma), float(game.tilt.beta))
	if tilt_first == Vector2.INF:
		tilt_first = reading_now
	return reading_now.distance_to(tilt_first) > 12.0


func _move_hands(delta: float) -> void:
	var v := _view().size
	var moving := step in [Step.COINS, Step.ANYONE, Step.CARD, Step.READ]
	for h in hands:
		var was := h.pos
		if h.device != "bot" and moving and not (step == Step.COINS and h.inserted >= 0.0):
			h.vel *= Game.friction(delta) * Game.friction(delta, 0.0, 1.0 - 1.0 / SPEED)
			if h.dir != Vector2.ZERO:
				h.vel = (h.vel + h.dir * SPEED * delta * Game.REFERENCE_FPS).limit_length(MAX_SPEED)
			if h.device == "mouse":
				h.vel = (h.vel + mouse_push * 3.0).limit_length(MAX_SPEED)
			var next := h.pos + h.vel * delta
			if next.x < COIN_R or next.x > v.x - COIN_R:
				h.vel.x *= -0.5
			if next.y < COIN_R or next.y > v.y - COIN_R:
				h.vel.y *= -0.5
			h.pos = (h.pos + h.vel * delta).clamp(Vector2(COIN_R, COIN_R), v - Vector2(COIN_R, COIN_R))
		elif not moving:
			h.vel = Vector2.ZERO      # hands on: their coins stay put while it spells
		h.spin += (h.pos.x - was.x) / COIN_R
	mouse_push = Vector2.ZERO


## The first level: roll your coin into a slot. Both slots, then the board.
func _coins(delta: float) -> void:
	for h in hands:
		if h.inserted < 0.0:
			for n in [1, 2]:
				if _in_slot(n) == null and h.pos.distance_to(_slot_pos(n)) < SLOT_MOUTH:
					h.slot = n
					h.inserted = 0.0
					h.spin = 0.0
					sounds.tray_close.play()
					if logging:
						print("%7.1f  %s is %dP" % [clock, h.label, n])
					break
		elif h.inserted < 1.0:
			h.inserted = minf(h.inserted + delta / 0.6, 1.0)
			h.pos = h.pos.lerp(_slot_pos(h.slot), minf(delta * 10.0, 1.0))
	var both := hands.size() == 2 and hands[0].inserted >= 1.0 and hands[1].inserted >= 1.0
	both_in = both_in + delta if both else 0.0
	if both_in > 1.2:
		_go(Step.ANYONE)
		return

	var options := []
	if Board.connected:
		options.append("balance board: step on")
	if _tilt_available():
		options.append("tilt: tilt your phone" if game.tilt.gamma != null else "tilt: tap, allow motion, then tilt")
	options.append("keyboard: arrows, or WASD")
	options.append("finger: drag" if DisplayServer.is_touchscreen_available() else "mouse: click and drag")
	hint_label.text = "pick a controller by using it:      " + "      ·      ".join(options)
	var coins_in := 0
	for h in hands:
		if h.inserted >= 0.0:
			coins_in += 1
	if coins_in == 1:
		big_label.text = "never play alone." if step_time < 12.0 or hands.size() > 1 else "never play alone.\n(nobody else here? your other hand counts.)"
	elif coins_in == 2:
		big_label.text = ""


func _slot_pos(n: int) -> Vector2:
	return _view().size * Vector2(0.34 if n == 1 else 0.66, 0.36)


# ---- spelling: player three has the pointer ---------------------------------------------------

## Player three takes the pointer to spell `word`, a letter at a time, once everyone's hands are on.
func _spell(word: String) -> void:
	spelling = word
	spell_i = 0
	spell_at = null
	spell_last = null
	spell_rest = 0.0
	listening = false
	spirit.target = Vector2.INF
	var how := []
	for h in hands:
		how.append("%dP: %s" % [h.slot, {"board": "stay on the board", "tilt": "hold the phone",
			"arrows": "hold an arrow key", "wasd": "hold a WASD key", "bot": "hold on",
			"mouse": "keep a finger down" if DisplayServer.is_touchscreen_available() else "hold the mouse button"}[h.device]])
	hint_label.text = "hands on.  be still.\n" + "      ".join(how)


## Every frame while it spells. True once it has finished, and rested a moment.
func _spelling(delta: float) -> bool:
	if not listening:
		for h in hands:
			if h.grip < HANDS_ON:
				return false
		listening = true                 # it has the pointer now
		hint_label.text = ""
		prey.threat = FAR
		prey.fear = 0.0
		prey.speed = SPELL_SPEED
		_volumes({"dusk": -26, "night_insects": -28})
		if logging:
			print("%7.1f  hands on: it has the pointer" % clock)
	var slipping := false
	for h in hands:
		if h.grip <= 0.0:
			_let_go(h)
			return false
		slipping = slipping or h.slipping
	hint_label.text = "hold on." if slipping else ""
	if spell_i >= spelling.length():
		spell_rest += delta
		if spell_rest > 1.5:
			listening = false
			prey.speed = 100.0
			_volumes({"dusk": -14, "night_insects": -16})
			hint_label.text = ""
			return true
		return false
	if spell_at == null:
		spell_at = _nearest_letter(spelling[spell_i])
		spell_rest = 0.0
	if prey.position.distance_to(spell_at.global_position) < 12.0 and prey.velocity.length() < 30.0:
		spell_rest += delta
		if spell_rest >= SPELL_REST:
			lit[spell_at] = 1.0
			told[-1] += spelling[spell_i]
			if logging:
				print("%7.1f  %s" % [clock, spelling[spell_i]])
			spell_last = spell_at
			spell_at = null
			spell_i += 1
			spell_rest = 0.0
	return false


## The nearest letter `ch` on the board (not the one it's on: GOODBYE has two O's).
func _nearest_letter(ch: String) -> Sprite2D:
	var best: Sprite2D = null
	for word in letters:
		for child in letters[word].get_children():
			var s := child as Sprite2D
			if s.get_meta("letter") != ch or s == spell_last:
				continue
			if best == null or s.global_position.distance_to(prey.position) < best.global_position.distance_to(prey.position):
				best = s
	return best


func _let_go(h: Hand) -> void:
	let_go = "%dP" % h.slot
	told[-1] += "—"
	if logging:
		print("%7.1f  %s let go" % [clock, let_go])
	_go(Step.TRANSCRIPT)


# ---- reading a word -------------------------------------------------------------------------

func _read(delta: float) -> bool:
	if target == Vector2.INF:
		return false
	var close: bool = prey.position.distance_to(target) < _target_radius()
	if step == Step.ANYONE:
		close = close or _on_word(letters.YES)   # YES counts anywhere on the word
	reading = reading + delta if close else maxf(reading - delta * 0.5, 0.0)
	return reading >= READ_HOLD


## The fingertip is on one of this row's letters.
func _target_radius() -> float:
	if step in [Step.CARD, Step.READ, Step.FINALE]:
		var card: Dictionary = data.cards[card_index] if card_index < data.cards.size() else data.secret
		if card.has("radius"):
			return card.radius * _card_scale()
	return READ_RADIUS * _card_scale()


func _on_word(row: Node2D) -> bool:
	for child in row.get_children():
		var s := child as Sprite2D
		var half := s.texture.get_size() * s.scale * 0.5
		if Rect2(s.global_position - half, half * 2.0).has_point(prey.position):
			return true
	return false


func _place_pointer(at: Vector2) -> void:
	prey.position = at
	prey.velocity = Vector2.ZERO
	prey.fear = 0.0


func _nudge_pointer_off_target() -> void:
	# a new card shouldn't be read before anyone has done anything
	_layout()
	if target != Vector2.INF and prey.position.distance_to(target) < 160.0:
		prey.velocity += (prey.position - target).normalized() * 80.0


# ---- layout (every frame: the window can change shape) ----------------------------------------

func _view() -> Rect2:
	return get_viewport_rect()


func _card_scale() -> float:
	var v := _view().size
	var w: float = card_sprite.texture.get_width() if card_sprite.texture != null else 760.0
	return minf(v.y * 0.97 / 560.0, v.x * 0.7 / w)


func _layout() -> void:
	var v := _view().size
	var k := _card_scale()
	font_px = int(clampf(v.y * 0.035, 16, 30))
	top_label.add_theme_font_size_override("font_size", int(font_px * (1.6 if step == Step.COINS else 1.0)))
	words_label.add_theme_font_size_override("font_size", font_px + 2)
	hint_label.add_theme_font_size_override("font_size", int(font_px * 0.7))
	big_label.add_theme_font_size_override("font_size", int(font_px * 0.8))
	top_label.position = Vector2(v.x * 0.05, v.y * 0.025)
	top_label.size = Vector2(v.x * 0.9, font_px * 3)
	hint_label.position = Vector2(v.x * 0.03, v.y - font_px * 2.4)
	hint_label.size = Vector2(v.x * 0.94, font_px * 2.2)

	# the card, as big as fits on the left; its caption in the space beside it
	var tex_size := card_sprite.texture.get_size() if card_sprite.texture != null else Vector2(760, 560)
	card_size = tex_size * k
	card_centre = Vector2(v.x * 0.015 + card_size.x * 0.5, v.y * 0.5)
	card_sprite.position = card_centre
	card_sprite.scale = Vector2(k, k)
	var column_x := card_centre.x + card_size.x * 0.5 + v.x * 0.015
	var column_w := v.x - column_x - v.x * 0.03
	caption.position = Vector2(column_x, v.y * 0.07)
	caption.size = Vector2(column_w, v.y * 0.66)
	# as big as fits: the caption fills its column, about three quarters of the way down
	var chars := 0
	for part in caption_parts:
		chars += part[0].length()
	caption.add_theme_font_size_override("normal_font_size", int(clampf(sqrt(column_w * v.y * 0.62 / (maxf(chars, 1) * 0.9)), 15.0, 30.0)))
	caption.visible = step in [Step.CARD, Step.READ, Step.FINALE]

	# the board: the clock in the middle, YES left, NO right, GOODBYE under it
	# (sized by the width too, so a phone held upright still fits YES and NO on the screen)
	var cs := minf(v.y * 0.42 / clock_sprite.texture.get_height(), v.x * 0.36 / clock_sprite.texture.get_width())
	var centre := v * Vector2(0.5, 0.42)
	clock_sprite.position = centre
	clock_sprite.scale = Vector2(cs, cs)
	var lsize := clampf(minf(v.y * 0.085, v.x * 0.075), 30, 110)
	var clock_half := clock_sprite.texture.get_size() * cs * 0.5
	_row(letters.YES, centre + Vector2(-clock_half.x - lsize * 2.2, 0), lsize)
	_row(letters.NO, centre + Vector2(clock_half.x + lsize * 1.7, 0), lsize)
	_row(letters.GOODBYE, centre + Vector2(0, clock_half.y + lsize * 0.95), lsize)

	# the corner clock
	var hk := clampf(v.y * 0.15, 60, 140) / 180.0
	if hour != shown_hour:
		hour_sprite.texture = load(data.hours.digital[hour - 1])
		shown_hour = hour
	hour_sprite.scale = Vector2(hk, hk)
	hour_sprite.position = Vector2(v.x - 180 * hk * 0.75, v.y - 180 * hk * 0.6)
	hour_sprite.visible = step in [Step.CARD, Step.READ, Step.FINALE]

	# the title and the end
	var tk := v.y * 0.7 / title_sprite.texture.get_height()
	title_sprite.position = v * Vector2(0.5, 0.47)
	title_sprite.scale = Vector2(tk, tk)
	var ek := minf(v.y * 0.2 / end_sprite.texture.get_height(), v.x * 0.2 / end_sprite.texture.get_width())
	end_sprite.position = Vector2(v.x - end_sprite.texture.get_width() * ek * 0.62, v.y - end_sprite.texture.get_height() * ek * 0.75)
	end_sprite.scale = Vector2(ek, ek)
	big_label.add_theme_color_override("font_color", PAPER)
	match step:
		Step.TITLE:
			# the title above the easel; the rules on its blank board, under the printed "RULES"
			top_label.text = TITLE.to_upper()
			top_label.add_theme_font_size_override("font_size", int(font_px * 1.6))
			var tw := title_sprite.texture.get_size() * tk
			var corner := title_sprite.position - tw * 0.5
			big_label.text = RULES
			big_label.position = corner + tw * Vector2(0.08, 0.14)
			big_label.size = tw * Vector2(0.48, 0.46)
			big_label.add_theme_font_size_override("font_size", int(clampf(tw.x * 0.045, 14, 30)))
			big_label.add_theme_color_override("font_color", Color(0.1, 0.08, 0.06))
		Step.COINS:
			big_label.position = Vector2(v.x * 0.1, v.y * 0.55)
			big_label.size = Vector2(v.x * 0.8, v.y * 0.14)
			big_label.add_theme_font_size_override("font_size", font_px)
		_:
			big_label.position = Vector2(v.x * 0.08, v.y * 0.06)
			big_label.size = Vector2(v.x * 0.84, v.y * 0.62)

	# where the word is
	match step:
		Step.ANYONE:
			target = letters.YES.position
		Step.CARD, Step.READ, Step.FINALE:
			var card: Dictionary = data.cards[card_index] if card_index < data.cards.size() else data.secret
			target = card_centre + (Vector2(card.target[0], card.target[1]) - Vector2(card.size[0], card.size[1]) * 0.5) * k
		_:
			target = Vector2.INF
	if step == Step.ANYONE or step == Step.CARD:
		spirit.target = target
	elif step == Step.READ:
		spirit.target = Vector2.INF
	spirit.settle_radius = READ_RADIUS * k * 1.5
	planchette.scale = Vector2(0.42, 0.42) * clampf(k, 0.6, 1.2)


func _row(row: Node2D, centre: Vector2, size: float) -> void:
	var n := row.get_child_count()
	row.position = centre
	for i in n:
		var s: Sprite2D = row.get_child(i)
		var glow: float = lit.get(s, 0.0)
		var k := size / s.texture.get_height() * (1.0 + 0.3 * glow)
		s.scale = Vector2(k, k)
		s.position = Vector2((i - (n - 1) * 0.5) * size * 1.02, 0)
		s.modulate = Color.WHITE.lerp(AMBER, glow)


# ---- the pointer, the coins, player three's hand -----------------------------------------------

func _update_planchette(delta: float) -> void:
	planchette.visible = step not in [Step.TITLE, Step.COINS, Step.TRANSCRIPT]
	planchette.position = prey.position
	# it points up and to the left, like a cursor, and only leans a little as it moves
	tilt_angle = lerpf(tilt_angle, clampf(prey.velocity.x / 100.0, -1.0, 1.0) * 0.3, minf(delta * 4.0, 1.0))
	planchette.rotation = -2.0 + tilt_angle
	planchette.modulate = Color(1, 1, 1, 1) if reading == 0.0 else Color(1, 1, 0.8 + 0.2 * sin(clock * 12.0), 1)


func _draw_marks() -> void:
	if step == Step.TITLE or step == Step.TRANSCRIPT:
		return
	if step == Step.FINALE and finale > 0.0:
		_draw_light()
	if step == Step.COINS:
		_draw_slot(1)
		_draw_slot(2)
	for h in hands:
		if not (step == Step.COINS and h.inserted >= 1.0):
			_draw_coin(h)


func _draw_slot(n: int) -> void:
	var c := _slot_pos(n)
	var h := _in_slot(n)
	var font := ThemeDB.fallback_font
	var plate := Rect2(c - Vector2(46, 64), Vector2(92, 128))
	marks.draw_rect(plate, Color(0.27, 0.19, 0.17))
	marks.draw_rect(plate, PAPER if h != null else DIM, false, 2.0)
	var lit_up := h != null and h.inserted >= 1.0
	marks.draw_rect(Rect2(c - Vector2(5, 26), Vector2(10, 52)), AMBER if lit_up else Color(0.03, 0.02, 0.02))
	marks.draw_string(font, c + Vector2(-60, -78), "%dP" % n, HORIZONTAL_ALIGNMENT_CENTER, 120, font_px * 2, AMBER if lit_up else PAPER)
	if h != null:
		marks.draw_string(font, c + Vector2(-120, 64 + font_px * 1.4), h.label, HORIZONTAL_ALIGNMENT_CENTER, 240, font_px, DIM)


## A player's coin, and their push: a small hand behind it, pointing the way they push.
func _draw_coin(h: Hand) -> void:
	var at := h.pos
	var alpha := 1.0
	if step == Step.WHO or step == Step.GOODBYE:
		alpha = 0.3 + 0.7 * h.grip
		if h.slipping:
			at += Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
	var k := COIN_R * 2.0 / maxf(h.coin.get_width(), h.coin.get_height())
	var squash := 1.0 - 0.85 * h.inserted if step == Step.COINS and h.inserted > 0.0 else 1.0
	marks.draw_set_transform(at, h.spin, Vector2(k * squash, k))
	marks.draw_texture(h.coin, -h.coin.get_size() * 0.5, Color(h.tint, alpha))
	# their push: a small hand on the coin's edge, pointing the way they push
	var m := minf(h.dir.length(), 1.0)
	if m > 0.05:
		var d := h.dir.normalized()
		marks.draw_set_transform(at + d * (COIN_R + 16.0 + 22.0 * m), d.angle(), Vector2(0.34, 0.34))
		marks.draw_texture(planchette.texture, -fingertip, Color(1, 1, 1, alpha * (0.6 + 0.4 * m)))
	marks.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Player three's hand: a pale copy of the pointer, turned the way it's pushing, as strong as
## its push. Faint while it helps; plain to see when it has the pointer.
func _draw_ghost() -> void:
	if not planchette.visible:
		return
	# the target lights up for a moment when it's read
	if hit_glow > 0.0 and target != Vector2.INF and step in [Step.READ, Step.FINALE]:
		var r := _target_radius() * (1.6 if _target_radius() < 60.0 else 1.1)
		over.draw_circle(target, r, Color(AMBER, 0.25 * hit_glow))
		over.draw_circle(target, r, Color(AMBER, 0.9 * hit_glow), false, 3.0)
	if step == Step.READ and step_time < SPARK_TIME + 0.3 and target != Vector2.INF:
		var t := clampf(step_time / SPARK_TIME, 0.0, 1.0)
		var to := caption.position + Vector2(caption.size.x * 0.3, caption.size.y * 0.25)
		var at := target.lerp(to, t * t * (3.0 - 2.0 * t))
		for i in 6:   # a short trail behind it
			var back := target.lerp(to, maxf(t - i * 0.04, 0.0) * maxf(t - i * 0.04, 0.0) * (3.0 - 2.0 * maxf(t - i * 0.04, 0.0)))
			over.draw_circle(back, 12.0 - i * 1.5, Color(AMBER, 0.5 - i * 0.07))
		over.draw_circle(at, 16.0, Color(1.0, 0.92, 0.7, 0.9))
	var a := clampf(ghost.length() / 90.0, 0.0, 0.7)
	if listening:
		a = maxf(a, 0.5)
	if a < 0.03:
		return
	# the same hand, shifted the way it's pulling
	var shift := ghost.normalized() * minf(ghost.length() * 0.4, 30.0) if ghost.length() > 0.0 else Vector2.ZERO
	over.draw_set_transform(prey.position + shift, planchette.rotation, planchette.scale * 1.05)
	over.draw_texture(planchette.texture, -fingertip, Color(GHOST, a))
	over.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---- the caption ----------------------------------------------------------------------------

## A caption with the card's words hidden in it, in [brackets].
func _set_caption(text: String) -> void:
	caption_parts.clear()
	hidden_count = 0
	revealed = 0
	reveal_to = 0
	var rest := text
	while rest.find("[") >= 0:
		var a := rest.find("[")
		var b := rest.find("]", a)
		caption_parts.append([rest.substr(0, a), -1])
		caption_parts.append([rest.substr(a + 1, b - a - 1), hidden_count])
		hidden_count += 1
		rest = rest.substr(b + 1)
	caption_parts.append([rest, -1])
	_show_caption()


func _show_caption() -> void:
	var out := ""
	for part in caption_parts:
		if part[1] >= 0 and part[1] < revealed:
			out += "[color=%s][u]%s[/u][/color]" % [HIDDEN_COLOR, part[0]]
		else:
			out += "[color=%s]%s[/color]" % [CAPTION_COLOR, part[0]]
	caption.text = out


# ---- the secret's ending ---------------------------------------------------------------------

## It takes the pointer where the fingers meet and holds it there; light comes down the beam
## in the picture and sweeps round until it fills the oval; then "you weren't"; then the end.
func _finale(delta: float) -> void:
	if not listening:
		for h in hands:
			if h.grip < HANDS_ON:
				return
		listening = true
		hint_label.text = ""
		prey.threat = FAR
		prey.fear = 0.0
		_volumes({"night_insects": -28})
	for h in hands:
		if h.grip <= 0.0:
			_let_go(h)
			return
	finale += delta
	if finale > 4.6 and revealed < hidden_count:
		revealed = hidden_count
		_show_caption()
	if finale > 7.0:
		_go(Step.TRANSCRIPT)


func _draw_light() -> void:
	var card: Dictionary = data.secret
	var k := _card_scale()
	var beam := card_centre + (Vector2(card.beam[0], card.beam[1]) - Vector2(card.size[0], card.size[1]) * 0.5) * k
	var start := (beam - card_centre).angle()
	var rx := card_size.x * 0.31
	var ry := card_size.y * 0.3
	var fade := clampf(finale / 1.2, 0.0, 1.0)
	var sweep := clampf((finale - 1.5) / 3.0, 0.0, 1.0)
	var half := deg_to_rad(10.0)
	var from := start - half
	var to := start + half + sweep * (TAU - 2.0 * half)
	var points := PackedVector2Array([card_centre])
	var n := 64
	for i in n + 1:
		var a := lerpf(from, to, float(i) / n)
		points.append(card_centre + Vector2(cos(a) * rx, sin(a) * ry))
	marks.draw_colored_polygon(points, Color(1.0, 0.93, 0.7, 0.42 * fade))


# ---- the coyotes -----------------------------------------------------------------------------

func _on_howl(near: bool) -> void:
	for name in ["coyotes_near", "coyotes_far", "lone_coyote", "siren_and_coyotes"]:
		if sounds[name].playing:
			return
	if _two_players():
		sounds["coyotes_near" if near else "coyotes_far"].play()   # together: a chorus answers
	else:
		sounds.lone_coyote.play()                                   # one hand doing it all: one calls


# ---- the transcript --------------------------------------------------------------------------

func _transcript() -> String:
	var lines: Array[String] = ["LUDUM DARE 60  ·  OCTOBER 2026", ""]
	lines.append_array(told)
	lines.append("")
	if let_go != "":
		lines.append("%s let go." % let_go)
		return "\n".join(lines)
	var parts := []
	for pair in spirit.shares():
		parts.append("%s %d%%" % ["player three" if pair[0] == "spirit" else pair[0], roundi(pair[1] * 100)])
	lines.append("who pushed it:   " + "  ·  ".join(parts))
	lines.append("it was mostly you. except when you held still.")
	return "\n".join(lines)


# ---- players for testing ---------------------------------------------------------------------

## `--keys`: the real arrow keys and WASD, pressed by the test (`--keys --mouse`: the arrow keys
## and a mouse drag). Both hold "up" (their coins roll straight up into the slots), skip ahead
## to "who are you?", hold on while it spells, then let go after six seconds. It should end
## with someone letting go.
func _keys_test() -> void:
	if step == Step.TITLE:
		_go(Step.COINS)
	if step == Step.ANYONE and step_time > 2.0:
		_go(Step.WHO)
	var hold := step == Step.COINS or (step == Step.WHO and step_time < 6.0)
	for action in ["ui_up"] if "--mouse" in args else ["ui_up", "p2_up"]:
		if hold:
			Input.action_press(action)
		else:
			Input.action_release(action)
	if "--mouse" in args:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = hold
		if hold != Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			Input.parse_input_event(button)
		if hold and step == Step.COINS:
			var drag := InputEventMouseMotion.new()
			drag.button_mask = MOUSE_BUTTON_MASK_LEFT
			drag.relative = Vector2(0, -3)
			Input.parse_input_event(drag)


## Bots roll their coins into the slots, then (with --bot or --letgo) push the pointer toward
## the word the way a person would: from behind it, then backing off to let it settle.
func _bot(delta: float) -> void:
	for i in hands.size():
		var h := hands[i]
		if h.device != "bot":
			continue
		var letting_go := "--letgo" in args and i == 1 and step == Step.WHO and spell_i >= 3
		h.grip = maxf(h.grip - delta * 0.5, 0.0) if letting_go else 1.0
		h.slipping = letting_go
		var goal := h.pos
		match step:
			Step.COINS:
				if h.inserted < 0.0:
					goal = _slot_pos(i + 1)
			Step.ANYONE, Step.CARD:
				if bots_push and target != Vector2.INF:
					var to_word := target - prey.position
					var dir := to_word.normalized()
					if i == 0:
						goal = prey.position - dir * prey.scare_radius * (0.55 if to_word.length() > 70.0 else 1.7)
					else:
						var side := (dir.orthogonal() * 0.5 - dir).normalized()
						goal = prey.position + side * prey.scare_radius * (0.6 if to_word.length() > 70.0 else 1.8)
		var was := h.pos
		h.pos = h.pos.move_toward(goal, (170.0 if i == 0 else 150.0) * delta).clamp(Vector2(COIN_R, COIN_R), _view().size - Vector2(COIN_R, COIN_R))
		h.dir = (h.pos - was).normalized() if h.pos != was else Vector2.ZERO
