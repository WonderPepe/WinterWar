extends Node
## Test for V10b "the battle leaves marks" (not part of the game):
##   godot --headless --path . --script tools/run.gd -- tools/test_v10b.gd
## Bodies: a fallen soldier's picture is handed to the BodyKeeper and stays when the soldier
## node is removed; caps per quality; a new day keeps the newest 24 with snow on them; a soldier
## killed in the air comes down. Tracks: a driving tank lays strips on the ground, one draw
## call, the pool wraps round, a new day clears them.

var fails := 0
var game: Node
var terrain: TerrainGenerator
var quality_before: int


## Stands in for the day screen: the test says when it is black.
class FakeDayScreen extends Node:
	var black: bool = false
	func is_black() -> bool:
		return black


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


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func spawn(i: int, pos: Vector3) -> Enemy:
	var e: Enemy = load("res://scenes/enemies/soviet_rifleman.tscn").instantiate()
	e.name = "Body%d" % i
	e.position = pos
	e.attack_point = pos
	game.get_node("Enemies").add_child(e, true)
	e.set_physics_process(false) # no AI: he just stands there
	return e


func ground(x: float, z: float) -> Vector3:
	return Vector3(x, terrain.get_height(x, z), z)


func run() -> void:
	Settings.difficulty = 1
	quality_before = Settings.quality
	check(Settings.PRESETS[Settings.Quality.LOW].max_bodies == 24 and Settings.PRESETS[Settings.Quality.MEDIUM].max_bodies == 24
			and Settings.PRESETS[Settings.Quality.HIGH].max_bodies == 36, "body caps are 24 / 24 / 36 (Low / Medium / High, V10c)")
	Settings.quality = Settings.Quality.HIGH
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_node("PauseMenu").free()
	await wait(0.5)
	var p: Player = get_tree().get_first_node_in_group("players")
	p.input.set_process(false)
	p.input.set_physics_process(false)
	p.set_physics_process(false)
	p.health = 100000
	(get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner).set_process(false)
	(get_tree().get_first_node_in_group("match_director") as MatchDirector).set_process(false)
	terrain = get_tree().get_first_node_in_group("terrain")
	# The test decides when the day screen is black.
	for n in get_tree().get_nodes_in_group("day_screen"):
		n.remove_from_group("day_screen")
	var screen := FakeDayScreen.new()
	screen.add_to_group("day_screen")
	add_child(screen)

	var keeper := game.get_node_or_null("Bodies") as BodyKeeper
	var tracks := game.get_node_or_null("TankTracks") as TankTracks
	check(keeper != null and keeper.is_in_group("body_keeper"), "the game has the Bodies node (BodyKeeper)")
	check(tracks != null and tracks.get_node_or_null("Strips") is MultiMeshInstance3D, "the game has the TankTracks node with one MultiMesh")
	if keeper == null or tracks == null:
		get_tree().quit(1)
		return
	check(keeper.keep_overnight == 24, "24 bodies stay for the next day (V10c)")

	# --- One soldier falls: his body stays, the soldier node goes.
	var e: Enemy = spawn(0, ground(0.0, 20.0))
	await frames(5)
	var visual: SoldierVisual = e.visual
	e.take_damage(1000.0, 1, e.global_position, Vector3.UP)
	check(e.state == Enemy.State.DEAD, "the soldier is dead")
	await wait(1.5)
	check(visual.get_parent() == e and not visual.is_body, "1.5 s after the fall he is still the soldier's own picture")
	await wait(2.0)
	check(visual.get_parent() == keeper and visual.is_body, "3.5 s after the fall the BodyKeeper has the body")
	check(not visual.is_processing(), "the body runs no script any more")
	check(is_instance_valid(e) and e.is_in_group("enemies"), "the soldier node is still there for a moment")
	var lying: Transform3D = visual.global_transform
	check(absf(lying.basis.y.y) < 0.3, "the body lies flat (it kept its place when handed over)")
	e.is_kneeling = true # a late change from the host must not move a kept body
	await frames(5)
	check(visual.global_transform.is_equal_approx(lying), "a late pose change does not move the body")
	check(not visual.baked.is_empty() and visual.get_node_or_null("Skeleton") == null, "V10c: the body is baked, his skeleton is gone")
	check(keeper.batch_count() == 1, "V10c: he is drawn by one batch (%d)" % keeper.batch_count())
	var mesh: MeshInstance3D = keeper.get_batch_nodes()[0] if keeper.batch_count() > 0 else null
	check(mesh != null and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and mesh.visibility_range_end > 100.0,
			"the body casts no shadow and is hidden far away (%d m)" % (mesh.visibility_range_end if mesh else 0.0))
	var aabb: AABB = mesh.get_aabb() if mesh else AABB()
	aabb = mesh.global_transform * aabb if mesh else aabb
	check(mesh != null and aabb.grow(0.2).has_point(visual.global_position) and aabb.size.y < 1.2 and aabb.size.length() > 1.0,
			"V10c: the batch shape lies where he fell, flat on the snow (%s)" % str(aabb.size))
	await wait(3.5)
	check(not is_instance_valid(e), "7 s after the fall the soldier node is gone")
	check(is_instance_valid(visual) and visual.is_inside_tree() and keeper.get_bodies().size() == 1, "...and the body is still on the field")
	var alive: int = 0
	for n in get_tree().get_nodes_in_group("enemies"):
		alive += 1
	check(alive == 0, "no bodies in the \"enemies\" group (AI, trench count and wave count don't see them)")

	# --- A soldier killed in the air comes down to the ground.
	var high: Vector3 = ground(6.0, 20.0)
	var e2: Enemy = spawn(1, high + Vector3.UP * 2.5)
	await frames(3)
	var v2: SoldierVisual = e2.visual
	e2.take_damage(1000.0, 1, e2.global_position, Vector3.UP)
	await wait(4.5)
	check(v2.is_body and absf(v2.global_position.y - high.y) < 0.2, "killed 2.5 m up in the air: the body ends on the ground (%.2f m above it)" % (v2.global_position.y - high.y))

	# --- The game paused right after a kill: the body is not lost.
	var e3: Enemy = spawn(2, ground(12.0, 20.0))
	await frames(3)
	var v3: SoldierVisual = e3.visual
	e3.take_damage(1000.0, 1, e3.global_position, Vector3.UP)
	await wait(1.0)
	get_tree().paused = true
	await wait(7.0) # (this test keeps running while the game is paused)
	check(is_instance_valid(e3) and not v3.is_body, "paused 1 s after a kill: nothing happens during the pause")
	get_tree().paused = false
	await wait(2.6)
	check(v3.is_body and v3.get_parent() == keeper, "after the pause the body is handed over as usual")
	await wait(3.0)
	check(not is_instance_valid(e3) and is_instance_valid(v3), "...and the soldier node goes, the body stays")

	# --- The cap: more than 36 bodies on High – the oldest sink into the snow.
	var group: Array[SoldierVisual] = []
	for i in 40:
		var s: Enemy = spawn(10 + i, ground(-40.0 + i * 2.0, 10.0))
		group.append(s.visual)
	await frames(3)
	for n in get_tree().get_nodes_in_group("enemies"):
		(n as Enemy).take_damage(1000.0, 1, (n as Enemy).global_position, Vector3.UP)
	await wait(3.6)
	check(keeper.get_bodies().size() == 36, "43 fallen on High: 36 bodies are kept (%d)" % keeper.get_bodies().size())
	check(not keeper.get_bodies().has(visual) and is_instance_valid(visual), "the oldest body is being taken away (sinking)")
	var y_before: float = visual.global_position.y
	await wait(1.0)
	check(is_instance_valid(visual) and visual.global_position.y < y_before - 0.1, "...it sinks into the snow")
	await wait(keeper.sink_time)
	check(not is_instance_valid(visual), "...and is gone after %.0f s" % keeper.sink_time)
	check(keeper.get_child_count() == 36 + keeper.batch_count(), "only the 36 kept bodies (+ %d batches) are left under Bodies (%d)" % [keeper.batch_count(), keeper.get_child_count()])
	var in_batches: int = 0
	var verts: int = 0
	for b in keeper.get_batch_nodes():
		verts += (b.mesh as ArrayMesh).surface_get_array_len(0)
	for b in keeper.get_bodies():
		in_batches += 1 if not b.baked.is_empty() else 0
	check(in_batches == 36 and verts == 36 * (visual_verts(keeper)), "V10c: all 36 bodies are baked into the batches (%d vertices)" % verts)
	check(keeper.batch_count() <= 10, "V10c: 36 bodies in a 80 m row are drawn with %d batches (draw calls), not 36" % keeper.batch_count())

	# --- Quality turned down: fewer bodies.
	Settings.quality = Settings.Quality.MEDIUM # (not set_quality: that would save it in the player's settings)
	Settings.changed.emit()
	await frames(2)
	check(keeper.get_bodies().size() == 24, "quality Medium: 24 bodies (%d)" % keeper.get_bodies().size())
	await wait(keeper.sink_time + 0.3)
	Settings.quality = Settings.Quality.LOW
	Settings.changed.emit()
	await frames(2)
	check(keeper.get_bodies().size() == 24, "V10c: quality Low: also 24 bodies (%d)" % keeper.get_bodies().size())
	Settings.quality = Settings.Quality.HIGH
	Settings.changed.emit()

	# --- A new day: the newest 24 stay, with snow on them. (Make it 30 first.)
	for i in 6:
		spawn(80 + i, ground(-30.0 + i * 2.0, 0.0))
	await frames(3)
	for n in get_tree().get_nodes_in_group("enemies"):
		(n as Enemy).take_damage(1000.0, 1, (n as Enemy).global_position, Vector3.UP)
	await wait(3.6)
	check(keeper.get_bodies().size() == 30, "30 bodies before the night (%d)" % keeper.get_bodies().size())
	var newest: SoldierVisual = keeper.get_bodies().back()
	check(newest.get_snow_cover() == 0.0, "a fresh body has no snow on it")
	screen.black = true
	await wait(0.8)
	check(keeper.get_bodies().size() == 24, "behind the black day screen: 24 bodies stay (%d)" % keeper.get_bodies().size())
	check(keeper.get_bodies().has(newest), "...the newest ones")
	check(newest.get_snow_cover() > 0.2, "...with snow on them (%.2f)" % newest.get_snow_cover())
	var snow_in_batch: bool = true
	for b in keeper.get_batch_nodes():
		var uv2: PackedVector2Array = (b.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
		snow_in_batch = snow_in_batch and uv2.size() > 0 and uv2[0].x > 0.2
	check(snow_in_batch and keeper.get_child_count() == 24 + keeper.batch_count(), "V10c: the batches carry the snow, the others are gone")
	await wait(1.2)
	check(keeper.get_bodies().size() == 24, "the day screen staying black changes nothing more")
	screen.black = false
	await wait(0.8)
	# The next day: 5 more fall; the night after, the newest 24 stay (5 new + 19 old).
	var fresh: Array[SoldierVisual] = []
	for i in 5:
		var s: Enemy = spawn(60 + i, ground(-10.0 + i * 2.0, 5.0))
		fresh.append(s.visual)
	await frames(3)
	for n in get_tree().get_nodes_in_group("enemies"):
		(n as Enemy).take_damage(1000.0, 1, (n as Enemy).global_position, Vector3.UP)
	await wait(3.6)
	check(keeper.get_bodies().size() == 29, "next day: 24 old + 5 new bodies (%d)" % keeper.get_bodies().size())
	var snow_first_night: float = newest.get_snow_cover()
	screen.black = true
	await wait(0.8)
	var kept: Array[SoldierVisual] = keeper.get_bodies()
	var all_fresh_kept: bool = true
	for f in fresh:
		all_fresh_kept = all_fresh_kept and kept.has(f)
	check(kept.size() == 24 and all_fresh_kept, "second night: 24 stay, all 5 new ones among them")
	check(newest.get_snow_cover() > snow_first_night and newest.get_snow_cover() <= 0.9, "a second night adds snow (%.2f, never more than 0.9)" % newest.get_snow_cover())
	check(fresh[0].get_snow_cover() < newest.get_snow_cover(), "yesterday's bodies have less snow than the older ones")
	screen.black = false
	await wait(0.8)

	# --- Tank tracks.
	var spawner := get_tree().get_first_node_in_group("tank_spawner") as TankSpawner
	var tank: Tank = spawner.spawn_tank(1)
	tank.set_physics_process(false) # the test drives it
	var start: Vector3 = ground(20.0, -40.0)
	tank.global_position = start
	await frames(3)
	check(tracks.visible_strips() == 0, "a tank that has just appeared (or was put somewhere) leaves no track")
	# 30 m north-east, 0.2 m per frame.
	var dir := Vector3(0.6, 0.0, 0.8)
	for i in 150:
		var at: Vector3 = start + dir * (0.2 * (i + 1))
		tank.global_position = ground(at.x, at.z)
		await get_tree().process_frame
	check(tracks.strips_laid >= 17 and tracks.strips_laid <= 20, "30 m driven: a strip about every 1.5 m (%d strips)" % tracks.strips_laid)
	check(tracks.visible_strips() == tracks.strips_laid, "all of them are shown")
	var worst_gap: float = 0.0
	var worst_height: float = 0.0
	var worst_turn: float = 0.0
	var worst_tilt: float = 0.0
	var last_end: Vector3 = start
	var half: float = tracks.strip_length * 0.5
	for i in tracks.strips_laid:
		var t: Transform3D = tracks.strip_transform(i)
		var from: Vector3 = t.origin + t.basis.z * half # (basis.z points back along the strip)
		var to: Vector3 = t.origin - t.basis.z * half
		worst_gap = maxf(worst_gap, Vector2(from.x - last_end.x, from.z - last_end.z).length())
		last_end = to
		worst_height = maxf(worst_height, absf(t.origin.y - terrain.get_height(t.origin.x, t.origin.z) - tracks.lift))
		worst_turn = maxf(worst_turn, rad_to_deg((-t.basis.z).slide(Vector3.UP).normalized().angle_to(dir)))
		worst_tilt = maxf(worst_tilt, rad_to_deg(t.basis.y.normalized().angle_to(Vector3.UP)))
	check(worst_gap < 0.02, "each strip starts where the one before ended (worst gap %.3f m)" % worst_gap)
	check(last_end.distance_to(tank.global_position) < tracks.strip_length + 0.3, "the track reaches up to the tank")
	check(worst_height < 0.12, "they lie on the ground (worst %.2f m off)" % worst_height)
	check(worst_turn < 2.0, "they point the way the tank drove (worst %.1f°)" % worst_turn)
	check(worst_tilt < 25.0, "they tilt with the ground, never upright (worst %.1f°)" % worst_tilt)
	var mmi := tracks.get_node("Strips") as MultiMeshInstance3D
	check(mmi.multimesh.instance_count == tracks.pool_size and mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"one MultiMesh pool of %d strips, no shadows" % tracks.pool_size)
	var mat := mmi.multimesh.mesh.surface_get_material(0) as StandardMaterial3D
	check(mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED,
			"the strips are see-through and lit like the snow (dark at night)")
	var img: Image = mat.albedo_texture.get_image()
	var mid_a: float = img.get_pixel(img.get_width() / 2, 3).a
	var rut_x: int = int((0.5 + tracks.rut_centre_m / tracks.strip_width) * img.get_width())
	var rut_a: float = img.get_pixel(rut_x, 3).a
	check(mid_a < 0.02 and rut_a > 0.6 and img.get_pixel(0, 3).a < 0.02, "the picture is two ruts, clear between and outside them (rut %.2f, middle %.2f)" % [rut_a, mid_a])
	# Put somewhere else at once: no strip across the field.
	var laid: int = tracks.strips_laid
	tank.global_position = ground(-60.0, -20.0)
	await frames(3)
	check(tracks.strips_laid == laid, "a tank moved at once (50 m) draws no strip across the field")
	# A standing tank (a wreck) lays nothing more.
	await wait(0.5)
	check(tracks.strips_laid == laid, "a standing tank lays nothing")
	# The pool wraps round: never more than pool_size strips shown.
	for i in tracks.pool_size + 10:
		tracks._lay(Vector3(i * 0.01, 0, 0), Vector3(i * 0.01, 0, -1.5))
	check(tracks.visible_strips() == tracks.pool_size, "a full pool reuses the oldest strips (%d shown)" % tracks.visible_strips())
	# A new day clears the tracks.
	screen.black = true
	await wait(0.8)
	check(tracks.visible_strips() == 0 and tracks.strips_laid == 0, "behind the black day screen the tracks are cleared")
	screen.black = false
	tank.global_position = ground(-60.0, 30.0)
	await frames(3)
	check(tracks.strips_laid == 0, "after the clearing a tank put somewhere else leaves no stray strip")
	for i in 16:
		tank.global_position = ground(-60.0, 30.0 - 0.2 * (i + 1))
		await get_tree().process_frame
	check(tracks.strips_laid == 2, "...and then the tank lays tracks again (%d)" % tracks.strips_laid)

	Settings.quality = quality_before as Settings.Quality
	print("TEST V10B DONE: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## V10c: how many corners one baked rifleman has (all riflemen use the same mesh).
func visual_verts(keeper: BodyKeeper) -> int:
	var b: Array[SoldierVisual] = keeper.get_bodies()
	return (b[0].baked[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if not b.is_empty() else -1
