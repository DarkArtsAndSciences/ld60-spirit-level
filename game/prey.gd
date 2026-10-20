extends Area2D

func _ready() -> void:
	add_to_group("prey")
	
var r := 20
var r2 := Vector2(r,r)
var scare_radius := 6 * r
var threat := Vector2.ZERO  # updated from Game
var velocity := Vector2.ZERO
var fear := 0.0
var speed := 100.0
var bounce := -0.5

func _physics_process(delta: float) -> void:
	# avoid threats
	var away := position - threat
	var new_fear := 0.0
	if away.length() < scare_radius:  # threat is close
		new_fear = (scare_radius - away.length()) / scare_radius
		fear += pow(new_fear, 0.5) * delta
	else:  # fear only goes down if no threats in range
		fear *= Game.friction(delta)
	%Readout.text = "prey fear: %.2f\nnew: %.2f" % [fear, new_fear]
	velocity *= Game.friction(delta, fear)  # while scared, it glides
	if (fear):
		velocity += away.normalized() * fear
	
	# bounce off walls
	var next := position + velocity * delta
	var screen_size := get_viewport_rect().size
	var clamped = next.clamp(r2*2, screen_size - r2*2)  # double edge width
	if next != clamped:
		if next.x != clamped.x: velocity.x *= bounce
		if next.y != clamped.y: velocity.y *= bounce
		velocity += (clamped - next) * 2.0
		print("prey bounce: %.2f %.2f" % [velocity.x, velocity.y])
	
	velocity = velocity.limit_length(speed)
	#%Readout.text += "\nprey velocity: %.1f %.1f" % [velocity.x, velocity.y]
	position = (position + velocity * delta).clamp(r2, screen_size - r2)
	
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, r, Color.REBECCA_PURPLE)
	draw_circle(Vector2.ZERO, r, Color.BLACK, false)
	draw_circle(Vector2.ZERO, scare_radius, Game.warning_color(fear), false)
	
	if (velocity.length() > 1):  # moving
		var on_circle = velocity.normalized() * r
		var how_fast  = velocity.length() / speed
		var start = on_circle*(1-how_fast)
		var end   = on_circle*(1+how_fast)
		draw_line  (start, end, Color.BLACK, 4)
