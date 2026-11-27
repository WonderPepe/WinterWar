class_name FinnMesh
extends RefCounted
## NET2b: the low-poly Finnish soldier the OTHER players see (your own body stays hidden).
##
## Built in code like the Soviet SoldierMesh and on the SAME 12-bone skeleton, so the same
## posing code (walking legs, arms reaching for the gun) works for him. One skinned mesh,
## one draw call. Two versions: with the Mosin M/28-30 and with the Suomi KP/-31.
##
## Look (owner, 2026-11-18): M/39 fur hat (grey fur, ear flaps tied up on top, grey cloth
## crown, cockade); a loose, dirty off-white snow smock to mid-thigh, gathered at the waist with
## a drawcord, the hood down and bunched round the back of the neck and shoulders; the grey
## uniform collar and cuffs just showing; full white snow trousers over brown leather boots
## (only the toe shows, a little turned up); grey-ivory wool mittens like the first-person arms.
## Subtle grime on the elbows, stomach, lower hem and knees. No pockets, zips or patterns.
##
## Vertex colour alpha = cloth type for soldier.gdshader: 1 = snow cloth (tint + grain),
## 0.5 = other cloth / fur (grain), 0 = skin, leather, metal, wood.

enum Gun { MOSIN, SUOMI }

const B := SoldierMesh.Bone

const SMOCK := Color(0.8, 0.79, 0.73, 1.0)        # warm, dirty ivory – same as the FP arms
const SMOCK_FOLD := Color(0.66, 0.65, 0.6, 1.0)   # the hood's folds, in shadow
const SMOCK_CORD := Color(0.6, 0.58, 0.52, 0.5)   # drawcord
const TROUSERS := Color(0.78, 0.77, 0.72, 1.0)    # snow trousers, a shade greyer than the smock
const TUNIC := Color(0.42, 0.43, 0.39, 0.5)       # grey wool uniform (collar, cuffs)
const WOOL := Color(0.72, 0.69, 0.63, 0.5)        # grey-ivory mittens
const FUR := Color(0.4, 0.38, 0.35, 0.5)          # grey fur of the M/39 hat
const FUR_DARK := Color(0.32, 0.3, 0.27, 0.5)
const CAP_CLOTH := Color(0.43, 0.44, 0.4, 0.5)    # grey cloth crown
const BOOT := Color(0.3, 0.19, 0.11, 0.0)         # brown leather
const SKIN := Color(0.8, 0.64, 0.55, 0.0)
const COCKADE_BLUE := Color(0.18, 0.28, 0.55, 0.0)
const COCKADE_WHITE := Color(0.85, 0.86, 0.84, 0.0)
const WOOD := Color(0.4, 0.25, 0.13, 0.0)
const METAL := Color(0.12, 0.12, 0.13, 0.0)
const SNOW := Color(0.9, 0.93, 0.98, 0.0)

const DIRT := Color(0.5, 0.47, 0.4)
const DIRT_STRENGTH: float = 0.5 ## How dark the grime gets at its worst (0 = none).

## Where the shots come from, in gun-bone space.
const MUZZLE_MOSIN: Vector3 = Vector3(0, 0.02, -0.74)
const MUZZLE_SUOMI: Vector3 = Vector3(0, 0.015, -0.5)
## Where the hands hold each gun, in gun-bone space: right hand (grip), left hand.
const GRIP_MOSIN: Vector3 = Vector3(0.0, -0.05, 0.12)
const FORE_MOSIN: Vector3 = Vector3(0.0, -0.03, -0.3)
const GRIP_SUOMI: Vector3 = Vector3(0.0, -0.06, 0.08)
const FORE_SUOMI: Vector3 = Vector3(0.0, -0.13, -0.13) # cups the drum's front-lower edge (AR3)

static var _cached: Dictionary = {} # Gun -> ArrayMesh


static func get_mesh(gun: int = Gun.MOSIN) -> ArrayMesh:
	if not _cached.has(gun):
		_cached[gun] = _build(gun)
	return _cached[gun]


static func muzzle_for(gun: int) -> Vector3:
	return MUZZLE_SUOMI if gun == Gun.SUOMI else MUZZLE_MOSIN


static func grip_for(gun: int) -> Vector3:
	return GRIP_SUOMI if gun == Gun.SUOMI else GRIP_MOSIN


static func fore_for(gun: int) -> Vector3:
	return FORE_SUOMI if gun == Gun.SUOMI else FORE_MOSIN


## Grime: darker where the cloth rubs and kneels in the snow and dirt (rest-pose positions).
static func _grime(p: Vector3, c: Color) -> Color:
	if c.a < 0.75:
		return c # only the snow cloth
	var d: float = 0.0
	for side in [-1.0, 1.0]:
		d = maxf(d, _spot(p, Vector3(side * 0.22, 1.13, 0.0), 0.09))      # elbows
		d = maxf(d, _spot(p, Vector3(side * 0.1, 0.49, -0.07), 0.1))      # knees
		d = maxf(d, _spot(p, Vector3(side * 0.22, 0.86, -0.02), 0.07) * 0.6) # sleeve ends
	d = maxf(d, _spot(p, Vector3(0.0, 1.12, -0.2), 0.13) * 0.7)          # stomach (lying on it)
	if p.y < 0.85 and p.y > 0.55:
		d = maxf(d, clampf((0.8 - p.y) / 0.1, 0.0, 1.0) * 0.8)           # lower hem
	if p.y < 0.2:
		d = maxf(d, clampf((0.2 - p.y) / 0.14, 0.0, 1.0) * 0.7)            # trouser bottoms
	var out: Color = c.lerp(DIRT, d * DIRT_STRENGTH)
	out.a = c.a
	return out


static func _spot(p: Vector3, center: Vector3, radius: float) -> float:
	return clampf(1.0 - p.distance_to(center) / radius, 0.0, 1.0)


static func _build(gun: int) -> ArrayMesh:
	SoldierMesh.begin_build()
	SoldierMesh.use_color_fn(_grime)

	# --- Upper body (spine): loose smock, gathered at the waist, grey collar, bunched hood ---
	SoldierMesh.use_bone(B.SPINE)
	SoldierMesh.frustum(Vector3(0, 0.99, 0), Vector3(0, 1.08, 0), 0.19, 0.2, 9, SMOCK, 0.76)   # gathered waist
	SoldierMesh.frustum(Vector3(0, 1.08, 0), Vector3(0, 1.4, 0), 0.215, 0.218, 9, SMOCK, 0.76) # loose chest
	SoldierMesh.frustum(Vector3(0, 1.4, 0), Vector3(0, 1.465, 0), 0.218, 0.1, 9, SMOCK, 0.76)  # shoulders
	SoldierMesh.frustum(Vector3(0, 1.025, 0), Vector3(0, 1.04, 0), 0.198, 0.198, 9, SMOCK_CORD, 0.77) # drawcord
	SoldierMesh.box(Vector3(-0.03, 0.98, -0.155), Vector3(0.012, 0.07, 0.01), SMOCK_CORD)     # cord ends
	SoldierMesh.box(Vector3(0.025, 0.975, -0.155), Vector3(0.012, 0.08, 0.01), SMOCK_CORD)
	SoldierMesh.frustum(Vector3(0, 1.44, 0), Vector3(0, 1.51, 0), 0.078, 0.072, 6, TUNIC)       # uniform collar
	# The hood, down: a thick roll of cloth round the back of the neck and onto the shoulders.
	SoldierMesh.sphere(Vector3(0, 1.485, 0.105), Vector3(0.15, 0.08, 0.085), 6, 3, SMOCK_FOLD) # roll at the neck
	SoldierMesh.sphere(Vector3(0, 1.515, 0.08), Vector3(0.105, 0.06, 0.065), 5, 3, SMOCK)
	for side in [-1.0, 1.0]:
		SoldierMesh.sphere(Vector3(side * 0.11, 1.475, 0.08), Vector3(0.06, 0.05, 0.07), 5, 2, SMOCK_FOLD)
	# The empty hood hanging down between the shoulder blades, with a fold across it.
	SoldierMesh.sphere(Vector3(0, 1.37, 0.205), Vector3(0.12, 0.12, 0.05), 6, 3, SMOCK)
	SoldierMesh.box(Vector3(0, 1.41, 0.245), Vector3(0.16, 0.022, 0.018), SMOCK_FOLD, Vector3(-0.3, 0, 0))
	SoldierMesh.box(Vector3(0.0, 1.465, 0.13), Vector3(0.09, 0.02, 0.06), SNOW) # a little snow in the fold

	# --- Smock skirt to mid-thigh: moves with the hips, the lower part follows the legs ---
	SoldierMesh.use_bone_fn(func(p: Vector3) -> Array:
		var leg: float = clampf((0.98 - p.y) / 0.3, 0.0, 1.0) * 0.7
		var side: float = clampf(0.5 + p.x / 0.25, 0.0, 1.0) # 0 = left, 1 = right
		return [PackedInt32Array([B.HIPS, B.THIGH_L, B.THIGH_R, 0]),
			PackedFloat32Array([1.0 - leg, leg * (1.0 - side), leg * side, 0.0])])
	SoldierMesh.frustum(Vector3(0, 0.99, 0), Vector3(0, 0.7, 0), 0.19, 0.25, 10, SMOCK, 0.82)

	# --- Head: neck, face, M/39 fur hat ---
	SoldierMesh.use_bone(B.HEAD)
	SoldierMesh.frustum(Vector3(0, 1.48, 0), Vector3(0, 1.56, 0), 0.05, 0.05, 6, SKIN)
	SoldierMesh.sphere(Vector3(0, 1.62, -0.01), Vector3(0.098, 0.108, 0.103), 8, 5, SKIN)
	SoldierMesh.frustum(Vector3(0, 1.655, 0.005), Vector3(0, 1.71, 0.005), 0.122, 0.124, 9, FUR)      # fur band
	SoldierMesh.frustum(Vector3(0, 1.71, 0.005), Vector3(0, 1.775, 0.01), 0.112, 0.1, 9, CAP_CLOTH)   # cloth crown
	SoldierMesh.frustum(Vector3(0, 1.775, 0.01), Vector3(0, 1.785, 0.01), 0.1, 0.07, 9, CAP_CLOTH)
	SoldierMesh.box(Vector3(0, 1.7, -0.123), Vector3(0.19, 0.075, 0.03), FUR, Vector3(-0.12, 0, 0))  # front flap, up
	SoldierMesh.box(Vector3(0, 1.69, 0.124), Vector3(0.2, 0.06, 0.03), FUR_DARK, Vector3(0.1, 0, 0)) # neck flap, up
	for side in [-1.0, 1.0]:
		# Ear flaps folded up and tied over the crown.
		SoldierMesh.box(Vector3(side * 0.112, 1.735, 0.005), Vector3(0.03, 0.1, 0.15), FUR, Vector3(0, 0, side * 0.32))
	SoldierMesh.box(Vector3(0, 1.79, 0.005), Vector3(0.02, 0.012, 0.03), FUR_DARK) # the tie on top
	SoldierMesh.box(Vector3(0, 1.705, -0.141), Vector3(0.032, 0.032, 0.006), COCKADE_BLUE) # cockade
	SoldierMesh.box(Vector3(0, 1.705, -0.145), Vector3(0.016, 0.016, 0.004), COCKADE_WHITE)
	SoldierMesh.box(Vector3(0, 1.788, 0.02), Vector3(0.11, 0.008, 0.1), SNOW)

	# --- Arms: loose smock sleeves, grey cuff peeking out, mittens ---
	for side in [-1.0, 1.0]:
		var upper: int = B.UPPER_ARM_L if side < 0 else B.UPPER_ARM_R
		var fore: int = B.FOREARM_L if side < 0 else B.FOREARM_R
		var shoulder := SoldierMesh.rest_global(upper)
		SoldierMesh.use_bone(upper)
		SoldierMesh.frustum(shoulder + Vector3(0, 0.03, 0), shoulder - Vector3(0, SoldierMesh.ARM_UPPER, 0), 0.075, 0.066, 6, SMOCK)
		var elbow := SoldierMesh.rest_global(fore)
		SoldierMesh.use_bone(fore)
		SoldierMesh.frustum(elbow + Vector3(0, 0.03, 0), elbow - Vector3(0, 0.22, 0), 0.067, 0.062, 6, SMOCK)
		SoldierMesh.frustum(elbow - Vector3(0, 0.2, 0), elbow - Vector3(0, 0.245, 0), 0.05, 0.048, 6, TUNIC) # cuff
		SoldierMesh.sphere(elbow - Vector3(0, 0.29, 0.0), Vector3(0.045, 0.058, 0.046), 5, 3, WOOL)            # mitten
		SoldierMesh.sphere(elbow - Vector3(-side * 0.03, 0.27, 0.03), Vector3(0.018, 0.03, 0.018), 4, 2, WOOL) # thumb

	# --- Legs: full snow trousers down over the boots; only the toes show ---
	for side in [-1.0, 1.0]:
		var thigh: int = B.THIGH_L if side < 0 else B.THIGH_R
		var shin: int = B.SHIN_L if side < 0 else B.SHIN_R
		var hip := SoldierMesh.rest_global(thigh)
		var knee := SoldierMesh.rest_global(shin)
		SoldierMesh.use_bone(thigh)
		SoldierMesh.frustum(hip + Vector3(0, 0.04, 0), knee, 0.09, 0.072, 6, TROUSERS)
		SoldierMesh.use_bone(shin)
		SoldierMesh.frustum(knee + Vector3(0, 0.03, 0), Vector3(knee.x, 0.07, 0.01), 0.072, 0.072, 6, TROUSERS)
		SoldierMesh.use_bone(B.FOOT_L if side < 0 else B.FOOT_R) # SV1: the foot bends at the ankle
		SoldierMesh.frustum(Vector3(knee.x, 0.085, 0.01), Vector3(knee.x, 0.035, 0.0), 0.073, 0.068, 6, TROUSERS) # bunched over the boot
		SoldierMesh.box(Vector3(knee.x, 0.035, -0.04), Vector3(0.085, 0.07, 0.2), BOOT)
		# Pieksu toe: turned up a little, not like an elf's.
		SoldierMesh.frustum(Vector3(knee.x, 0.04, -0.12), Vector3(knee.x, 0.07, -0.175), 0.036, 0.012, 5, BOOT)

	# --- The gun (gun bone) ---
	SoldierMesh.use_bone(B.RIFLE)
	var r := SoldierMesh.rest_global(B.RIFLE)
	if gun == Gun.SUOMI:
		_build_suomi(r)
	else:
		_build_mosin(r)
	return SoldierMesh.finish_build()


## Mosin-Nagant M/28-30: no bayonet fixed.
static func _build_mosin(r: Vector3) -> void:
	SoldierMesh.box(r + Vector3(0, -0.03, 0.25), Vector3(0.045, 0.1, 0.34), WOOD)  # butt
	SoldierMesh.box(r + Vector3(0, 0.0, -0.2), Vector3(0.04, 0.045, 0.62), WOOD)   # stock to the front band
	SoldierMesh.frustum(r + Vector3(0, 0.02, 0.06), r + Vector3(0, 0.02, -0.74), 0.012, 0.011, 5, METAL)
	SoldierMesh.box(r + Vector3(0, 0.025, 0.06), Vector3(0.03, 0.035, 0.12), METAL)  # receiver
	SoldierMesh.box(r + Vector3(0.04, 0.02, 0.1), Vector3(0.05, 0.012, 0.012), METAL) # bolt handle


## Suomi KP/-31: wooden stock, receiver, the long perforated barrel jacket, the round drum.
static func _build_suomi(r: Vector3) -> void:
	SoldierMesh.box(r + Vector3(0, -0.035, 0.24), Vector3(0.045, 0.095, 0.3), WOOD)  # butt
	SoldierMesh.box(r + Vector3(0, -0.02, 0.0), Vector3(0.042, 0.06, 0.24), WOOD)    # fore stock
	SoldierMesh.frustum(r + Vector3(0, 0.02, 0.14), r + Vector3(0, 0.02, -0.1), 0.022, 0.022, 6, METAL) # receiver
	SoldierMesh.frustum(r + Vector3(0, 0.015, -0.1), r + Vector3(0, 0.015, -0.5), 0.02, 0.02, 6, METAL)  # barrel jacket
	# Drum magazine in front of the trigger guard, standing on edge.
	SoldierMesh.frustum(r + Vector3(-0.035, -0.1, -0.03), r + Vector3(0.035, -0.1, -0.03), 0.085, 0.085, 10, METAL)
