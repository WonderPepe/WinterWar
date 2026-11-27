extends Node
## SV1: paints the Soviet soldier's face texture (assets/textures/soldier_face.png) – eyes,
## brows, nose, mouth and a little colour in the cheeks, neutral (owner, 27 Nov 2026).
## Not part of the game; run again only to change the face:
##   godot --headless --path . --script tools/run.gd -- tools/make_soldier_face.gd
##
## The picture is the FRONT of the face (SoldierMesh.face_uv): every feature is given in metres
## on the soldier (x across, y height), so it lines up with the head's shape. Transparent
## everywhere else – there the skin colour of the mesh shows.

const SIZE: int = 128
const OUT: String = "res://assets/textures/soldier_face.png"

# [x, y, radius x, radius y, colour, alpha, mirrored to the other side]
const FEATURES: Array = [
	[0.052, 1.585, 0.022, 0.016, Color(0.84, 0.52, 0.46), 0.14, true],   # cheeks, a little red from the cold
	[0.034, 1.617, 0.022, 0.012, Color(0.6, 0.44, 0.37), 0.55, true],   # eye socket shade
	[0.034, 1.617, 0.0125, 0.0045, Color(0.82, 0.78, 0.72), 0.95, true], # white of the eye
	[0.033, 1.6168, 0.0046, 0.0046, Color(0.22, 0.17, 0.13), 1.0, true], # iris
	[0.034, 1.6213, 0.015, 0.0026, Color(0.25, 0.17, 0.14), 0.85, true], # upper lid
	[0.035, 1.633, 0.017, 0.0032, Color(0.32, 0.24, 0.18), 0.9, true],   # brow
	[0.007, 1.5775, 0.004, 0.0025, Color(0.35, 0.22, 0.2), 0.7, true],   # nostril
	[0.0, 1.553, 0.021, 0.0048, Color(0.64, 0.4, 0.36), 0.6, false],     # lips
	[0.0, 1.553, 0.019, 0.0014, Color(0.3, 0.17, 0.15), 0.9, false],     # mouth line
	[0.0, 1.528, 0.022, 0.006, Color(0.66, 0.5, 0.42), 0.25, false],     # shade under the lower lip
]


func _ready() -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for f in FEATURES:
		_blob(img, f[0], f[1], f[2], f[3], f[4], f[5])
		if f[6]:
			_blob(img, -f[0], f[1], f[2], f[3], f[4], f[5])
	img.save_png(OUT)
	print("saved ", OUT)
	get_tree().quit()


## One soft-edged oval, painted over what is there (alpha "over").
func _blob(img: Image, x: float, y: float, rx: float, ry: float, col: Color, alpha: float) -> void:
	var c: Vector2 = SoldierMesh.face_uv(Vector3(x, y, -0.1)) * SIZE
	var r := Vector2(rx / SoldierMesh.FACE_UV_WIDTH, ry / SoldierMesh.FACE_UV_HEIGHT) * SIZE
	for py in range(maxi(0, int(c.y - r.y - 2)), mini(SIZE, int(c.y + r.y + 3))):
		for px in range(maxi(0, int(c.x - r.x - 2)), mini(SIZE, int(c.x + r.x + 3))):
			# 4 × 4 samples per pixel, so small features keep a smooth edge.
			var cover: float = 0.0
			for sy in 4:
				for sx in 4:
					var d := Vector2((px + (sx + 0.5) / 4.0 - c.x) / maxf(r.x, 0.5), (py + (sy + 0.5) / 4.0 - c.y) / maxf(r.y, 0.5))
					cover += 1.0 - smoothstep(0.6, 1.0, d.length())
			var a: float = alpha * cover / 16.0
			if a <= 0.0:
				continue
			var dst: Color = img.get_pixel(px, py)
			var out_a: float = a + dst.a * (1.0 - a)
			var rgb: Color = (col * a + dst * dst.a * (1.0 - a)) / out_a
			img.set_pixel(px, py, Color(rgb.r, rgb.g, rgb.b, out_a))
