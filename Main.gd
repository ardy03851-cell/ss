extends Node2D

# ==========================================
# ULTIMATE PHYSICS MINING GAME - V4
# Upgrades: Smooth Jump Physics & Modern UI
# ==========================================

var player: CharacterBody2D
var player_vis: ColorRect
var camera: Camera2D
var pause_menu: CanvasLayer
var hud_depth: Label
var hud_ores: Label
var hud_bombs: Label
var hud_container: MarginContainer

var blocks_container: Node2D
var debris_container: Node2D
var mining_laser: Line2D
var is_paused := false

# World Settings
var block_size := 40
var world_width := 45
var world_height := 70
var cave_noise: FastNoiseLite
var ore_noise: FastNoiseLite

# Progression
var ores_collected := 0
var bombs_inventory := 0
var speed_level := 1
var jump_level := 1

# Physics & Juice
var base_speed := 300.0
var base_jump := -500.0
const ACCELERATION = 2500.0
const FRICTION = 3000.0
var gravity = 1200.0
var fall_gravity_multiplier = 1.6 # Makes falling feel heavier/snappier
var shake_strength: float = 0.0
var was_on_floor := true
var physics_material: PhysicsMaterial

func _ready():
	process_mode = Node.PROCESS_MODE_PAUSABLE
	RenderingServer.set_default_clear_color(Color.BLACK)
	randomize()
	
	physics_material = PhysicsMaterial.new()
	physics_material.bounce = 0.4
	physics_material.friction = 0.8
	
	setup_noise()
	setup_environment()
	setup_world()
	setup_player()
	setup_ui()

# ==========================================
# POST-PROCESSING & ENVIRONMENT
# ==========================================
func setup_noise():
	cave_noise = FastNoiseLite.new()
	cave_noise.seed = randi()
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cave_noise.frequency = 0.08
	
	ore_noise = FastNoiseLite.new()
	ore_noise.seed = randi()
	ore_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	ore_noise.frequency = 0.15

func setup_environment():
	var darkness = CanvasModulate.new()
	darkness.color = Color(0.02, 0.02, 0.03) 
	add_child(darkness)
	
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 1.5
	env.glow_bloom = 0.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env_node.environment = env
	add_child(env_node)
	
	var bg_layer = CanvasLayer.new()
	bg_layer.layer = -1
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.04, 0.04)
	bg_layer.add_child(bg)
	add_child(bg_layer)

# ==========================================
# WORLD GENERATION
# ==========================================
func setup_world():
	blocks_container = Node2D.new()
	add_child(blocks_container)
	debris_container = Node2D.new()
	add_child(debris_container)
	
	for x in range(world_width):
		for y in range(5, world_height):
			if cave_noise.get_noise_2d(x, y) > 0.15: continue
			create_block(Vector2(x * block_size, y * block_size), x, y, false)
			
		create_block(Vector2(x * block_size, world_height * block_size), x, world_height, true)
			
	create_boundary(-block_size, 0, block_size, (world_height + 2) * block_size)
	create_boundary(world_width * block_size, 0, block_size, (world_height + 2) * block_size)

func create_block(pos: Vector2, grid_x: int, grid_y: int, is_bedrock: bool):
	var block = StaticBody2D.new()
	block.position = pos
	
	var col = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(block_size, block_size)
	col.shape = rect
	block.add_child(col)
	
	var vis = ColorRect.new()
	vis.size = Vector2(block_size - 2, block_size - 2)
	vis.position = Vector2(-block_size/2.0 + 1, -block_size/2.0 + 1)
	
	if is_bedrock:
		vis.color = Color(1.5, 0.3, 0.1)
		block.set_meta("is_bedrock", true)
		block.set_meta("is_ore", false)
	else:
		var is_ore = ore_noise.get_noise_2d(grid_x, grid_y) > 0.4 and grid_y > 10
		vis.color = Color(2.5, 2.5, 2.5) if is_ore else Color(0.15, 0.15, 0.15)
		block.set_meta("is_bedrock", false)
		block.set_meta("is_ore", is_ore)
		
	block.add_child(vis)
	
	var occluder = LightOccluder2D.new()
	var occ_poly = OccluderPolygon2D.new()
	occ_poly.polygon = PackedVector2Array([
		Vector2(-block_size/2.0, -block_size/2.0),
		Vector2(block_size/2.0, -block_size/2.0),
		Vector2(block_size/2.0, block_size/2.0),
		Vector2(-block_size/2.0, block_size/2.0)
	])
	occluder.occluder = occ_poly
	block.add_child(occluder)
	
	blocks_container.add_child(block)

func create_boundary(x, y, w, h):
	var bounds = StaticBody2D.new()
	bounds.position = Vector2(x + w/2.0, y + h/2.0)
	var col = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(w, h)
	col.shape = rect
	bounds.add_child(col)
	add_child(bounds)

# ==========================================
# PLAYER & CAMERA SETUP
# ==========================================
func setup_player():
	player = CharacterBody2D.new()
	player.position = Vector2((world_width * block_size) / 2.0, 100)
	
	var col = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(block_size - 12, block_size - 12)
	col.shape = rect
	player.add_child(col)
	
	player_vis = ColorRect.new()
	player_vis.size = Vector2(block_size - 12, block_size - 12)
	# Center the pivot for clean rotation and scaling
	player_vis.position = Vector2(-(block_size - 12)/2.0, -(block_size - 12)/2.0)
	player_vis.pivot_offset = player_vis.size / 2.0 
	player_vis.color = Color(1.8, 1.8, 1.8) 
	player.add_child(player_vis)
	
	var light = PointLight2D.new()
	var grad = Gradient.new()
	grad.add_point(0.0, Color.WHITE)
	grad.add_point(1.0, Color.TRANSPARENT)
	var tex = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1, 0.5)
	tex.width = 900
	tex.height = 900
	light.texture = tex
	light.shadow_enabled = true
	light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
	player.add_child(light)
	
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.zoom = Vector2(1.1, 1.1)
	player.add_child(camera)
	
	var dust = CPUParticles2D.new()
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(800, 600)
	dust.amount = 150
	dust.lifetime = 5.0
	dust.gravity = Vector2(0, -10)
	dust.initial_velocity_min = 5.0
	dust.initial_velocity_max = 20.0
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 4.0
	dust.color = Color(0.5, 0.5, 0.5, 0.4)
	camera.add_child(dust)
	
	mining_laser = Line2D.new()
	mining_laser.width = 3.0
	mining_laser.default_color = Color(2.0, 2.0, 2.0)
	add_child(mining_laser)
	
	add_child(player)

# ==========================================
# PHYSICS & GAME LOOP
# ==========================================
func _physics_process(delta):
	if is_paused: return
	
	var current_speed = base_speed + (speed_level * 30.0)
	var direction = Input.get_axis("ui_left", "ui_right")
	
	# ADVANCED JUMP PHYSICS
	if not player.is_on_floor():
		# Heavier falling gravity
		var applied_gravity = gravity * fall_gravity_multiplier if player.velocity.y > 0 else gravity
		player.velocity.y += applied_gravity * delta
		
		# Variable jump height: releasing the jump button early cuts upward velocity
		if Input.is_action_just_released("ui_up") and player.velocity.y < 0:
			player.velocity.y *= 0.4 
		
		# Air squash & stretch
		player_vis.scale.y = move_toward(player_vis.scale.y, 1.3, delta * 4)
		player_vis.scale.x = move_toward(player_vis.scale.x, 0.7, delta * 4)
	else:
		# Landing squash
		if not was_on_floor:
			player_vis.scale = Vector2(1.5, 0.5)
			trigger_shake(3.0)
			
		# Return to normal shape
		player_vis.scale.y = move_toward(player_vis.scale.y, 1.0, delta * 12)
		player_vis.scale.x = move_toward(player_vis.scale.x, 1.0, delta * 12)
		
		if Input.is_action_just_pressed("ui_up"):
			player.velocity.y = base_jump - (jump_level * 40.0)
			player_vis.scale = Vector2(0.5, 1.5) # Stretch on jump

	was_on_floor = player.is_on_floor()

	# Movement & Visual Tilt
	if direction:
		player.velocity.x = move_toward(player.velocity.x, direction * current_speed, ACCELERATION * delta)
		player_vis.rotation = lerp_angle(player_vis.rotation, direction * 0.15, delta * 12) # Tilt into run
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, FRICTION * delta)
		player_vis.rotation = lerp_angle(player_vis.rotation, 0.0, delta * 15) # Straighten out

	player.move_and_slide()
	handle_mining()
	handle_dynamite()
	process_physics_debris(delta)
	
	hud_depth.text = "DEPTH: " + str(max(0, int(player.position.y / block_size) - 4)) + "M"
	hud_bombs.text = "BOMBS: " + str(bombs_inventory) + " (Key 'B')"

func _process(delta):
	if shake_strength > 0:
		shake_strength = lerpf(shake_strength, 0, 12 * delta)
		camera.offset = Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength))
	
	if Input.is_action_just_pressed("ui_cancel"):
		toggle_pause()

# ==========================================
# MINING LOGIC
# ==========================================
func handle_mining():
	var mine_target = Vector2.ZERO
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_down"):
		mine_target = player.position + Vector2(0, block_size)
	elif Input.is_action_just_pressed("ui_left"): mine_target = player.position + Vector2(-block_size, 0)
	elif Input.is_action_just_pressed("ui_right"): mine_target = player.position + Vector2(block_size, 0)
	elif Input.is_action_just_pressed("ui_up"): mine_target = player.position + Vector2(0, -block_size)
		
	if mine_target != Vector2.ZERO: attempt_mine(mine_target)

func attempt_mine(target_pos: Vector2):
	for block in blocks_container.get_children():
		if block.position.distance_to(target_pos) < block_size * 0.8:
			draw_laser(player.position, block.position)
			if block.get_meta("is_bedrock"):
				trigger_shake(8.0)
				spawn_physics_debris(block.position, false, true) 
				var vis = block.get_child(1)
				var tw = create_tween()
				tw.tween_property(vis, "color", Color.WHITE, 0.05)
				tw.tween_property(vis, "color", Color(1.5, 0.3, 0.1), 0.1)
				return
				
			var is_ore = block.get_meta("is_ore")
			trigger_shake(12.0 if is_ore else 6.0)
			spawn_physics_debris(block.position, is_ore, false)
			block.queue_free()
			return

func draw_laser(start: Vector2, end: Vector2):
	mining_laser.clear_points()
	mining_laser.add_point(start)
	mining_laser.add_point(end)
	mining_laser.modulate.a = 1.0
	var tween = create_tween()
	tween.tween_property(mining_laser, "modulate:a", 0.0, 0.15)

func trigger_shake(strength: float): shake_strength = strength

func spawn_physics_debris(pos: Vector2, is_ore: bool, is_sparks: bool):
	var chunks = randi() % 3 + 2
	for i in range(chunks):
		var debris = RigidBody2D.new()
		debris.position = pos + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		debris.physics_material_override = physics_material
		var col = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		var s = randf_range(4, 8) if is_sparks else randf_range(8, 14)
		rect.size = Vector2(s, s)
		col.shape = rect
		debris.add_child(col)
		var vis = ColorRect.new()
		vis.size = Vector2(s, s)
		vis.position = Vector2(-s/2.0, -s/2.0)
		if is_sparks:
			vis.color = Color(2.0, 1.0, 0.5)
			debris.set_meta("is_ore", false)
		else:
			vis.color = Color(2.5, 2.5, 2.5) if is_ore else Color(0.25, 0.25, 0.25)
			debris.set_meta("is_ore", is_ore)
		debris.add_child(vis)
		debris.apply_central_impulse(Vector2(randf_range(-200, 200), randf_range(-400, -100)))
		debris.angular_velocity = randf_range(-15, 15)
		debris_container.add_child(debris)
		if not is_ore:
			get_tree().create_timer(3.0 if is_sparks else 5.0).timeout.connect(func(): if is_instance_valid(debris): debris.queue_free())

func process_physics_debris(delta):
	for debris in debris_container.get_children():
		if debris.get_meta("is_ore"):
			var dist = debris.global_position.distance_to(player.global_position)
			if dist < 120.0:
				debris.gravity_scale = 0
				var dir = (player.global_position - debris.global_position).normalized()
				debris.linear_velocity = dir * 400.0
				
				if dist < 20.0:
					collect_ore()
					debris.queue_free()

func collect_ore():
	ores_collected += 1
	hud_ores.text = "ORES: " + str(ores_collected)
	trigger_shake(2.0)
	
	# UI Pop Animation
	hud_container.pivot_offset = hud_container.size / 2.0
	var tween = create_tween()
	tween.tween_property(hud_container, "scale", Vector2(1.15, 1.15), 0.05).set_trans(Tween.TRANS_BACK)
	tween.tween_property(hud_container, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BOUNCE)

# ==========================================
# EXPLOSIVE DYNAMITE SYSTEM
# ==========================================
func handle_dynamite():
	if Input.is_action_just_pressed("ui_text_bold") or Input.is_physical_key_pressed(KEY_B):
		if bombs_inventory > 0:
			bombs_inventory -= 1
			spawn_bomb()

func spawn_bomb():
	var bomb = RigidBody2D.new()
	bomb.position = player.position + Vector2(0, -10)
	bomb.physics_material_override = physics_material
	var col = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	col.shape = rect
	bomb.add_child(col)
	var vis = ColorRect.new()
	vis.size = Vector2(16, 16)
	vis.position = Vector2(-8, -8)
	vis.color = Color.WHITE
	bomb.add_child(vis)
	bomb.apply_central_impulse(Vector2(player.velocity.x * 0.5, -200))
	bomb.angular_velocity = randf_range(-15, 15)
	var tween = create_tween().set_loops()
	tween.tween_property(vis, "color", Color.BLACK, 0.1)
	tween.tween_property(vis, "color", Color.WHITE, 0.1)
	debris_container.add_child(bomb)
	get_tree().create_timer(2.0).timeout.connect(func(): detonate_bomb(bomb))

func detonate_bomb(bomb: RigidBody2D):
	if not is_instance_valid(bomb): return
	var b_pos = bomb.global_position
	var blast_radius = 120.0
	trigger_shake(30.0)
	for block in blocks_container.get_children():
		if block.position.distance_to(b_pos) < blast_radius:
			if block.get_meta("is_bedrock"): continue
			spawn_physics_debris(block.position, block.get_meta("is_ore"), false)
			block.queue_free()
	for debris in debris_container.get_children():
		if debris == bomb: continue
		var dist = debris.global_position.distance_to(b_pos)
		if dist < blast_radius * 1.5:
			var dir = (debris.global_position - b_pos).normalized()
			var force = (1.0 - (dist / (blast_radius * 1.5))) * 1200.0
			debris.apply_central_impulse(dir * force)
	var flash = ColorRect.new()
	flash.size = Vector2(blast_radius*2, blast_radius*2)
	flash.position = b_pos - Vector2(blast_radius, blast_radius)
	flash.color = Color(2.0, 2.0, 2.0)
	debris_container.add_child(flash)
	var t = create_tween()
	t.tween_property(flash, "scale", Vector2.ZERO, 0.3)
	t.tween_callback(flash.queue_free)
	bomb.queue_free()

# ==========================================
# MODERN UI & STORE
# ==========================================
var speed_btn: Button
var jump_btn: Button
var bomb_btn: Button

func setup_ui():
	var ui_canvas = CanvasLayer.new()
	
	# Setup Rounded Panel Theme
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.05, 0.8)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.2, 0.2, 0.2, 1.0)
	
	# Main HUD Container
	hud_container = MarginContainer.new()
	hud_container.position = Vector2(20, 20)
	ui_canvas.add_child(hud_container)
	
	var hud_bg = PanelContainer.new()
	hud_bg.add_theme_stylebox_override("panel", panel_style)
	hud_container.add_child(hud_bg)
	
	var hud_margins = MarginContainer.new()
	hud_margins.add_theme_constant_override("margin_left", 15)
	hud_margins.add_theme_constant_override("margin_right", 15)
	hud_margins.add_theme_constant_override("margin_top", 10)
	hud_margins.add_theme_constant_override("margin_bottom", 10)
	hud_bg.add_child(hud_margins)
	
	var hud_vbox = VBoxContainer.new()
	hud_margins.add_child(hud_vbox)
	
	hud_depth = Label.new()
	hud_depth.add_theme_font_size_override("font_size", 18)
	hud_depth.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hud_vbox.add_child(hud_depth)
	
	hud_ores = Label.new()
	hud_ores.text = "ORES: 0"
	hud_ores.add_theme_font_size_override("font_size", 22)
	hud_ores.add_theme_color_override("font_color", Color(1.5, 1.5, 1.5)) # Glow text
	hud_vbox.add_child(hud_ores)
	
	hud_bombs = Label.new()
	hud_bombs.add_theme_font_size_override("font_size", 16)
	hud_bombs.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	hud_vbox.add_child(hud_bombs)
	
	add_child(ui_canvas)
	
	# Shop Menu
	pause_menu = CanvasLayer.new()
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.85)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	pause_menu.add_child(overlay)
	
	var shop_panel = PanelContainer.new()
	shop_panel.add_theme_stylebox_override("panel", panel_style)
	shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_child(shop_panel)
	
	var shop_margins = MarginContainer.new()
	shop_margins.add_theme_constant_override("margin_left", 40)
	shop_margins.add_theme_constant_override("margin_right", 40)
	shop_margins.add_theme_constant_override("margin_top", 30)
	shop_margins.add_theme_constant_override("margin_bottom", 30)
	shop_panel.add_child(shop_margins)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	shop_margins.add_child(vbox)
	
	var title = Label.new()
	title.text = "- S H O P -"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)
	
	speed_btn = Button.new()
	speed_btn.pressed.connect(func(): buy_upgrade("speed"))
	vbox.add_child(speed_btn)
	
	jump_btn = Button.new()
	jump_btn.pressed.connect(func(): buy_upgrade("jump"))
	vbox.add_child(jump_btn)
	
	bomb_btn = Button.new()
	bomb_btn.pressed.connect(func(): buy_upgrade("bomb"))
	vbox.add_child(bomb_btn)
	
	var quit_btn = Button.new()
	quit_btn.text = "RESUME"
	quit_btn.pressed.connect(toggle_pause)
	vbox.add_child(quit_btn)
	
	update_store_ui()
	add_child(pause_menu)

func toggle_pause():
	is_paused = !is_paused
	get_tree().paused = is_paused
	pause_menu.get_child(0).visible = is_paused
	update_store_ui()

func update_store_ui():
	var speed_cost = speed_level * 5
	var jump_cost = jump_level * 5
	var bomb_cost = 2
	
	speed_btn.text = "UPGRADE SPEED (COST: " + str(speed_cost) + " ORES)"
	jump_btn.text = "UPGRADE JUMP (COST: " + str(jump_cost) + " ORES)"
	bomb_btn.text = "BUY 3 DYNAMITE (COST: " + str(bomb_cost) + " ORES)"
	
	speed_btn.disabled = ores_collected < speed_cost
	jump_btn.disabled = ores_collected < jump_cost
	bomb_btn.disabled = ores_collected < bomb_cost

func buy_upgrade(type: String):
	if type == "speed" and ores_collected >= (speed_level * 5):
		ores_collected -= (speed_level * 5); speed_level += 1
	elif type == "jump" and ores_collected >= (jump_level * 5):
		ores_collected -= (jump_level * 5); jump_level += 1
	elif type == "bomb" and ores_collected >= 2:
		ores_collected -= 2; bombs_inventory += 3
	update_store_ui()
