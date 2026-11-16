extends Node
## Test for D9 "hit zones" (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_d9.gd
## A bullet's zone (head / body / legs) comes from where on the soldier's one capsule it lands -
## standing, kneeling and lying flat - and multiplies the damage. Fire and shells are untouched.

var fails := 0
var game: Node
var p: Player
var terrain: TerrainGenerator
var last_zone: int = -1
var last_killed: bool = false
var confirms: int = 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _ready() -> void:
	await get_tree().process_frame
	run()


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## A fresh soldier on open ground, AI switched off.
func spawn(kind: String = "rifleman") -> Enemy:
	var e: Enemy = load("res://scenes/enemies/soviet_%s.tscn" % kind).instantiate()
	e.position = Vector3(0.0, terrain.get_height(0.0, 0.0) + 0.05, 0.0)
	e.attack_point = e.position
	game.get_node("Enemies").add_child(e, true)
	e.set_physics_process(false)
	e.set_process(false)
	return e


## Fires one bullet of weapon `w` at the point `local` (in the soldier's own coordinates),
## from 4 m to his side and a little above. Returns the health he lost.
func shoot(e: Enemy, w: WeaponData, local: Vector3) -> float:
	var target: Vector3 = e.to_global(local)
	var origin: Vector3 = target + e.global_transform.basis.x * 4.0 + Vector3.UP * 0.6
	var before: float = e.health
	last_zone = -1
	p.weapons.resolve_shot(origin, (target - origin).normalized(), w, [])
	return before - e.health


func run() -> void:
	Settings.difficulty = 1
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await get_tree().create_timer(0.5).timeout
	p = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.set_physics_process(false)
	(get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner).set_process(false)
	terrain = get_tree().get_first_node_in_group("terrain")
	p.global_position = Vector3(0.0, terrain.get_height(0.0, 30.0) + 0.05, 30.0)
	p.weapons.hit_confirmed.connect(func(killed: bool, zone: int) -> void:
		confirms += 1
		last_killed = killed
		last_zone = zone)
	var mosin: WeaponData = p.weapons.loadout[0]
	var suomi: WeaponData = p.weapons.loadout[1]
	check(mosin.damage == 100.0 and suomi.damage == 25.0, "weapon damage unchanged (Mosin 100, Suomi 25)")
	var marker: HitMarker = game.get_node("HUD/HitMarker")

	# --- Standing soldier: zones by height.
	var e := spawn()
	await frames(3)
	check(e.data.head_damage_multiplier == 4.0 and e.data.leg_damage_multiplier == 0.6, "multipliers: head 4, legs 0.6")
	check(e.hit_zone_at(e.to_global(Vector3(0.33, 1.65, 0))) == Enemy.HitZone.HEAD, "standing 1.65 m = head")
	check(e.hit_zone_at(e.to_global(Vector3(0.33, 1.49, 0))) == Enemy.HitZone.BODY, "standing 1.49 m = body")
	check(e.hit_zone_at(e.to_global(Vector3(0.33, 0.86, 0))) == Enemy.HitZone.BODY, "standing 0.86 m = body")
	check(e.hit_zone_at(e.to_global(Vector3(0.33, 0.84, 0))) == Enemy.HitZone.LEGS, "standing 0.84 m = legs")

	# Suomi (25): legs 15, body 25, head 100 = dead.
	var lost: float = shoot(e, suomi, Vector3(0, 0.4, 0))
	check(is_equal_approx(lost, 15.0) and last_zone == Enemy.HitZone.LEGS and not last_killed, "Suomi in the legs: 15 damage (%.1f)" % lost)
	check(not marker._head, "leg hit: plain hit marker")
	lost = shoot(e, suomi, Vector3(0, 1.2, 0))
	check(is_equal_approx(lost, 25.0) and last_zone == Enemy.HitZone.BODY, "Suomi in the body: 25 damage (%.1f)" % lost)
	e.health = 100.0
	shoot(e, suomi, Vector3(0, 1.65, 0))
	check(e.state == Enemy.State.DEAD and last_killed and last_zone == Enemy.HitZone.HEAD, "Suomi in the head: one shot kills")
	check(marker._head and marker._color == marker.kill_color, "head-shot kill: red marker with the ring")

	# Mosin (100): body kills as before, legs only wound, a second leg hit kills.
	e = spawn()
	await frames(3)
	shoot(e, mosin, Vector3(0, 1.2, 0))
	check(e.state == Enemy.State.DEAD and last_zone == Enemy.HitZone.BODY, "Mosin in the body: still one shot")
	check(not marker._head, "body kill: no ring")
	e = spawn()
	await frames(3)
	lost = shoot(e, mosin, Vector3(0, 0.4, 0))
	check(is_equal_approx(lost, 60.0) and e.state != Enemy.State.DEAD, "Mosin in the legs: 60 damage, wounded (%.1f)" % lost)
	shoot(e, mosin, Vector3(0, 0.4, 0))
	check(e.state == Enemy.State.DEAD, "second Mosin leg hit kills")

	# --- Kneeling (1.2 m tall).
	e = spawn()
	await frames(3)
	e.is_kneeling = true
	await frames(3)
	lost = shoot(e, suomi, Vector3(0, 0.2, 0))
	check(last_zone == Enemy.HitZone.LEGS and is_equal_approx(lost, 15.0), "kneeling 0.2 m = legs")
	lost = shoot(e, suomi, Vector3(0, 0.65, 0))
	check(last_zone == Enemy.HitZone.BODY and is_equal_approx(lost, 25.0), "kneeling 0.65 m = body")
	shoot(e, suomi, Vector3(0, 1.05, 0))
	check(last_zone == Enemy.HitZone.HEAD and e.state == Enemy.State.DEAD, "kneeling 1.05 m = head")

	# --- Lying flat, head forward: zones along the body.
	e = spawn()
	await frames(3)
	e.is_prone = true
	await frames(3)
	lost = shoot(e, suomi, Vector3(0, 0.3, 0.4))
	check(last_zone == Enemy.HitZone.LEGS and is_equal_approx(lost, 15.0), "prone: rear of the body = legs")
	lost = shoot(e, suomi, Vector3(0, 0.3, -0.2))
	check(last_zone == Enemy.HitZone.BODY and is_equal_approx(lost, 25.0), "prone: middle = body")
	shoot(e, suomi, Vector3(0, 0.3, -0.85))
	check(last_zone == Enemy.HitZone.HEAD and e.state == Enemy.State.DEAD, "prone: front end = head")
	# From straight ahead (how the player usually sees a prone soldier) the bullet meets the head.
	e = spawn()
	await frames(3)
	e.is_prone = true
	await frames(3)
	var front: Vector3 = e.to_global(Vector3(0, 0.6, -6.0))
	p.weapons.resolve_shot(front, (e.to_global(Vector3(0, 0.3, -0.9)) - front).normalized(), mosin, [])
	check(last_zone == Enemy.HitZone.HEAD, "prone, shot from the front = head")

	# --- Officer and machine-gunner use the same zones.
	for kind: String in ["officer", "mg_gunner"]:
		e = spawn(kind)
		await frames(3)
		e.is_prone = false
		e.is_kneeling = false
		await frames(3)
		e.health = 100.0
		shoot(e, suomi, Vector3(0, 1.65, 0))
		check(last_zone == Enemy.HitZone.HEAD and e.state == Enemy.State.DEAD, "%s: head zone works" % kind)

	# --- Fire, shells, bombs: take_damage() directly, no zones.
	e = spawn()
	await frames(3)
	e.take_damage(25.0, 1, e.to_global(Vector3(0, 1.7, 0)), Vector3.UP)
	check(is_equal_approx(e.health, 75.0), "direct damage at head height is not multiplied")
	e.take_damage(25.0, 1, e.global_position, Vector3.UP)
	check(is_equal_approx(e.health, 50.0), "direct damage at the feet is not reduced")

	print("TEST D9 DONE: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)
