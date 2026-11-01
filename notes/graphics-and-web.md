# Web export, graphics settings, P1 graphics

Moved from CLAUDE.md (2026-11-01). Read when working on this area; keep it up to date.

## Web export limits (Compatibility renderer) – decisions already made
- No volumetric fog → depth + height fog. No Decal node → pooled quads (`ImpactEffects`).
- Crouch is **C** (Ctrl also bound, but Ctrl+W closes browser tabs).
- Snow = CPUParticles3D following the local player only. Trees = MultiMesh chunks with
  visibility ranges. One shadowed sun, short shadow distance. Only the local muzzle flash has
  a light. Export without threads. Navigation mesh is pre-baked (no runtime baking).
- CSG trench/bunker should be converted to static meshes before the web export (M5).
- Max 16 enemies alive; enemy senses run ~5×/s; no RVO avoidance.

## Graphics settings & web build
- Quality presets live in `autoload/settings.gd` (`PRESETS`); `scripts/game/quality_applier.gd`
  applies them (groups `sun`, `forest`, `world_environment`, players' snow).
- Tonemapper is **Linear** on purpose: in Compatibility, Filmic looks different when
  `scaling_3d_scale` < 1, so presets would change the colours.
- `display/window/stretch/mode = canvas_items` so UI scales with the browser window.
- Terrain mesh does not cast shadows (it doubled the triangle count for nothing).
- Web export preset "Web" (no threads) → `export/web/` (git-ignored). Export from the command
  line: `godot --headless --path . --export-release "Web" export/web/index.html` (needs the
  4.7.2 export templates). `python3 tools/web_smoke_test.py` checks it in headless Chromium.
- Measured budget (High, after P1): ~190 draw calls (260 max), ~255k triangles/frame, CPU scripts
  1–2 ms + physics 2.5–4 ms with 16 enemies (native). Keep new art within the README's budget table.

## Graphics (P1) – how it is built
- Look: stylized-realistic, clear freezing day, low warm sun in the SSW (in front-left of the
  trench), blue sky ambient → blue shadows. Linear tonemap, exposure 0.85, sun energy 1.25.
- Shaders in `resources/shaders/`; materials (`resources/materials/*.tres`) are written by
  `build_scenes.gd` (`_shader_mat`). Textures in `assets/textures/` come from
  `tools/make_textures.py` (FFT noise → tileable). Import settings: VRAM compressed + mipmaps
  (`snow_mask.png` lossless: it holds data, sparkle dots), normal-map detection disabled –
  shaders decode normals themselves (`xy * 2 - 1`).
- Snow/log shaders map textures by **world position** (CSG UVs are stretched).
- Terrain vertex colour for the snow shader: R < 1 = ice (bog), G < 1 = trampled snow
  (trench floor). Meshes without vertex colours read as white = plain snow.
- Forest LOD is decided **per tree in the spruce shader** (dithered cross-fade over
  `fade_band` m), not per chunk – whole 50 m chunks switching at once looked like random
  popping. `ForestScatter._process` passes the camera position (`lod_camera`) to its own copies
  of the tree materials (near = `lod_mode` 0, far = 1); shadow pass can't use the shader's camera.
  Chunk visibility ranges are only coarse culling, widened by the chunk radius.
  Per chunk: `Near0_*`/`Near1_*` (detailed; neighbouring chunks alternate the two shapes, one
  draw call each), `Shadow_*` (simple tree, shadows only, near range), `Far_*` (simple tree, no
  shadows – sun shadows end before it starts). `TreeLine` ring (radius 330/520 m).
  Trunk material is the same shader with `trunk = true` (bark texture).
  Per-tree values go in the MultiMesh **instance colour** (B = snow, A = tint); spruce vertex
  colour R = can hold snow, G = AO, B/A = 1; UV.x = 0 at trunk … 1 at branch tips.
  Tree *look* uses its own RNG so positions (and the baked navmesh) stay unchanged.
- Quality presets also set `tree_detail_distance` (35/50/70 m).
- Benchmark turns V-Sync off on desktop (else FPS is capped at the monitor rate). Godot's
  TIME_PROCESS includes CPU-side rendering, so the benchmark shows physics time only.
