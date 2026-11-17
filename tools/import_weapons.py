"""Unpacks the downloaded weapon and vehicle models (assets_source/*.zip, glTF from Sketchfab) into
assets/models/weapons/<name>/ (vehicles: assets/models/vehicles/<name>/) and shrinks their textures so the web download stays small.
Not part of the game. Run from the project folder:  python3 tools/import_weapons.py
Needs Pillow. The F-1 grenade (GR1) also needs numpy + meshoptimizer (pip install meshoptimizer):
    python3 tools/import_weapons.py --f1
T6: the T-26 also gets its wheel data (which vertex turns around which axle – see
bake_t26_wheels). To write only that into the model that is already unpacked (no zip needed):
    python3 tools/import_weapons.py --t26-wheels
"""
import io
import json
import math
import os
import struct
import sys
import zipfile
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets_source")
DST = os.path.join(ROOT, "assets", "models", "weapons")
VEHICLES = os.path.join(ROOT, "assets", "models", "vehicles")

# zip file -> (folder name, max texture size for colour/normal maps, max size for the rest)
MODELS = {
    "mosin_nagant_m91.zip": ("mosin", 1024, 512),
    "suomi_kp-31.zip": ("suomi", 1024, 512),
    "machine_gun_maxim.zip": ("maxim", 512, 512),
    "-26_sd.zip": ("t26", 1024, 512),  # T-26 tank (Sketchfab "Т-26 SD"; the file name lost its Cyrillic T)
}
# Vehicles go to assets/models/vehicles/. Their "specularf0" maps are dropped (Godot ignores
# KHR_materials_specular anyway – they would only make the download bigger).
VEHICLE_FOLDERS = {"t26"}


def shrink(data: bytes, name: str, max_size: int) -> tuple[bytes, str]:
    img = Image.open(io.BytesIO(data))
    img.load()
    if max(img.size) > max_size:
        scale = max_size / max(img.size)
        img = img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)
    base = os.path.splitext(name)[0]
    out = io.BytesIO()
    if "baseColor" in name and img.mode in ("RGB", "L"):
        img.save(out, "JPEG", quality=90)
        return out.getvalue(), base + ".jpg"
    img.save(out, "PNG", optimize=True)
    return out.getvalue(), base + ".png"


def drop_specular(gltf: dict) -> None:
    """Removes KHR_materials_specular and the images only it used (keeps indices consistent)."""
    for mat in gltf.get("materials", []):
        mat.get("extensions", {}).pop("KHR_materials_specular", None)
        if not mat.get("extensions"):
            mat.pop("extensions", None)
    for key in ("extensionsUsed", "extensionsRequired"):
        if key in gltf:
            gltf[key] = [e for e in gltf[key] if e != "KHR_materials_specular"]
            if not gltf[key]:
                del gltf[key]
    used = {m["pbrMetallicRoughness"]["baseColorTexture"]["index"] for m in gltf.get("materials", [])
            if "baseColorTexture" in m.get("pbrMetallicRoughness", {})}
    tex_map, new_tex = {}, []
    for i, t in enumerate(gltf.get("textures", [])):
        if i in used:
            tex_map[i] = len(new_tex)
            new_tex.append(t)
    img_used = sorted({t["source"] for t in new_tex})
    img_map = {old: new for new, old in enumerate(img_used)}
    for t in new_tex:
        t["source"] = img_map[t["source"]]
    gltf["textures"] = new_tex
    gltf["images"] = [gltf["images"][i] for i in img_used]
    for m in gltf.get("materials", []):
        bct = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if bct:
            bct["index"] = tex_map[bct["index"]]


# --- T6: wheel data for the T-26 -------------------------------------------------------------
# The tank's wheels are not separate parts: sprocket, idler, road wheels and return rollers are
# all welded into ONE "chassis" mesh per side. So that the wheels can still turn, every vertex
# of a wheel gets told which axle it belongs to. That goes into the mesh's second UV channel
# (glTF TEXCOORD_1 = Godot UV2), which the model didn't use:
#     UV2.x = the axle's place along the tank (metres, mesh space: +y = towards the nose)
#     UV2.y = the axle's height (metres) + 2 × the wheel's kind
#             kind 1 = drive sprocket / idler, 2 = road wheel, 3 = return roller
#     UV2 = (0, 0) = not a wheel (bogies, springs, brackets): never moves.
# resources/shaders/tank_wheels.gdshader turns each vertex around its axle; the TrackAnimator
# (scripts/enemies/track_animator.gd) tells it how far. The radii live in the TrackAnimator.
#
# (kind, along the tank, height) – read off the model; the exact axle is then measured from it.
T26_WHEELS = [
    (1, 1.818, 0.790),   # drive sprocket (front, with its 16 teeth and 6 spokes)
    (1, -1.962, 0.516),  # idler (rear)
    (2, 1.338, 0.191), (2, 0.940, 0.191), (2, 0.529, 0.191), (2, 0.133, 0.191),  # 8 road wheels
    (2, -0.228, 0.191), (2, -0.626, 0.191), (2, -1.042, 0.191), (2, -1.439, 0.198),
    (3, 1.168, 0.917), (3, 0.355, 0.859), (3, -0.411, 0.809), (3, -1.237, 0.749),  # 4 return rollers
]
T26_WHEEL_RADIUS = {1: 0.322, 2: 0.161, 3: 0.142}  # metres (the same numbers as in track_animator.gd)
T26_KIND_STEP = 2.0  # every axle is lower than 2 m, so "height + 2 × kind" can be taken apart again


def _accessor_span(gltf: dict, index: int) -> tuple[int, int, int]:
    """(byte offset of the first element, bytes from one element to the next, count)."""
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    size = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]] * 4  # floats / uint32 only
    return view.get("byteOffset", 0) + acc.get("byteOffset", 0), view.get("byteStride", 0) or size, acc["count"]


def bake_t26_wheels(out_dir: str) -> None:
    """Writes the wheel data (see above) into model.gltf + scene.bin. Safe to run again."""
    gltf_path = os.path.join(out_dir, "model.gltf")
    with open(gltf_path) as f:
        gltf = json.load(f)
    bin_path = os.path.join(out_dir, gltf["buffers"][0]["uri"])
    with open(bin_path, "rb") as f:
        data = bytearray(f.read())
    total = 0
    for mesh in gltf["meshes"]:
        if not mesh["name"].startswith("chassis"):
            continue
        prim = mesh["primitives"][0]
        off, stride, count = _accessor_span(gltf, prim["attributes"]["POSITION"])
        pos = [struct.unpack_from("<3f", data, off + i * stride) for i in range(count)]
        acc = gltf["accessors"][prim["indices"]]
        if acc["componentType"] != 5125:
            raise SystemExit("T-26 wheels: expected 32-bit indices")
        off, stride, n = _accessor_span(gltf, prim["indices"])
        idx = struct.unpack_from("<%dI" % n, data, off)

        # 1. Which vertices hang together? (Vertices at the same spot count as one; every
        #    triangle joins its three corners. Each wheel, tooth and bracket is its own "island".)
        spot: dict = {}
        welded = [spot.setdefault((round(p[0], 4), round(p[1], 4), round(p[2], 4)), len(spot)) for p in pos]
        parent = list(range(len(spot)))

        def root(a: int) -> int:
            while parent[a] != a:
                parent[a] = parent[parent[a]]
                a = parent[a]
            return a

        for t in range(0, n, 3):
            a = root(welded[idx[t]])
            parent[root(welded[idx[t + 1]])] = a
            parent[root(welded[idx[t + 2]])] = a
        islands: dict = {}
        for i in range(count):
            islands.setdefault(root(welded[i]), []).append(i)

        # 2. Each island's box seen from the side (y = along the tank, z = up).
        boxes = {}
        for key, verts in islands.items():
            ys = [pos[i][1] for i in verts]
            zs = [pos[i][2] for i in verts]
            boxes[key] = ((min(ys) + max(ys)) / 2.0, (min(zs) + max(zs)) / 2.0,
                          max(max(ys) - min(ys), max(zs) - min(zs)) / 2.0)

        # 3. Find every wheel and collect the islands that turn with it.
        uv2 = [(0.0, 0.0)] * count
        used: set = set()
        for kind, wy, wz in T26_WHEELS:
            radius = T26_WHEEL_RADIUS[kind]
            # The wheel itself: the round island sitting on this axle with the right size.
            discs = [k for k, (cy, cz, half) in boxes.items()
                     if math.hypot(cy - wy, cz - wz) < 0.02 and abs(half - radius) < 0.015]
            if not discs:
                raise SystemExit("T-26 wheels: no wheel found at (%.3f, %.3f) in %s" % (wy, wz, mesh["name"]))
            ay, az, _ = boxes[max(discs, key=lambda k: len(islands[k]))]  # the measured axle
            for key, verts in islands.items():
                cy, cz, half = boxes[key]
                reach = max(math.hypot(pos[i][1] - ay, pos[i][2] - az) for i in verts)
                if kind == 1:
                    # Sprocket / idler: everything inside its circle turns (discs, hub, spokes,
                    # bolts, and the teeth that stick out 5 cm past the rim).
                    part = reach < radius + 0.05
                else:
                    # Road wheels / rollers: only the disc itself. (The pin through the hub sits
                    # a few mm off-centre in the model and would wobble if it turned.)
                    part = math.hypot(cy - ay, cz - az) < 0.005 and half > radius * 0.5 and reach < radius + 0.01
                if not part:
                    continue
                if key in used:
                    raise SystemExit("T-26 wheels: a part belongs to two wheels in " + mesh["name"])
                used.add(key)
                for i in verts:
                    uv2[i] = (ay, az + T26_KIND_STEP * kind)
        moving = sum(1 for u in uv2 if u != (0.0, 0.0))
        total += moving

        # 4. Store it as TEXCOORD_1 (overwritten in place if it is already there).
        packed = b"".join(struct.pack("<2f", *u) for u in uv2)
        if "TEXCOORD_1" in prim["attributes"]:
            off, stride, _ = _accessor_span(gltf, prim["attributes"]["TEXCOORD_1"])
            if stride != 8:
                raise SystemExit("T-26 wheels: unexpected TEXCOORD_1 layout")
            data[off:off + len(packed)] = packed
            acc = gltf["accessors"][prim["attributes"]["TEXCOORD_1"]]
        else:
            while len(data) % 4:
                data.append(0)
            gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(data), "byteLength": len(packed),
                                        "byteStride": 8, "name": "wheelAxles", "target": 34962})
            data += packed
            acc = {"bufferView": len(gltf["bufferViews"]) - 1, "componentType": 5126, "count": count, "type": "VEC2"}
            gltf["accessors"].append(acc)
            prim["attributes"]["TEXCOORD_1"] = len(gltf["accessors"]) - 1
        acc["min"] = [min(u[0] for u in uv2), min(u[1] for u in uv2)]
        acc["max"] = [max(u[0] for u in uv2), max(u[1] for u in uv2)]
        print("  %s: %d wheels, %d of %d vertices turn" % (mesh["name"], len(T26_WHEELS), moving, count))
    if total == 0:
        raise SystemExit("T-26 wheels: no chassis mesh found")
    gltf["buffers"][0]["byteLength"] = len(data)
    with open(bin_path, "wb") as f:
        f.write(data)
    with open(gltf_path, "w") as f:
        json.dump(gltf, f, indent=1)


# --- GR1: the Soviet F-1 hand grenade -----------------------------------------------------------
# Sketchfab "Grenade F-1 / Ф-1 Лимонка" (chyzhykov.roman, CC-BY 4.0). The download is far too heavy for
# a 12 cm grenade (4,108 triangles, three 2048 px textures), so this one is rebuilt instead of copied:
#   - the four parts are baked into metres (body 55 mm across, 112 mm tall with the fuze), origin = the
#     middle of the body, +y = up (fuze on top);
#   - "Body" = cast-iron body + fuze, "Lever" = the safety lever (on the hand-held grenade only – it
#     flies off when the grenade is thrown); the pin + ring are left out (already pulled);
#   - each part is simplified with meshoptimizer (keeps the UVs: it only drops triangles);
#   - one material: colour + normal map at 256 px, no metal/roughness map (fixed values instead).
F1_ZIP = "Grenade F_1.zip"
F1_DIAMETER_M = 0.055
F1_PARTS = {"Body": ("f_1_main_low", "f_1_zapal_low"), "Lever": ("f_1_extractor_low",)}
F1_TARGET_TRIS = {"f_1_main_low": 300, "f_1_zapal_low": 120, "f_1_extractor_low": 60}


def import_f1() -> None:
    import numpy as np
    import meshoptimizer as mo
    path = os.path.join(SRC, F1_ZIP)
    if not os.path.exists(path):
        print("missing", F1_ZIP, "- skipped")
        return
    zf = zipfile.ZipFile(path)
    gltf_name = next(n for n in zf.namelist() if n.endswith(".gltf"))
    src = json.loads(zf.read(gltf_name))
    prefix = os.path.dirname(gltf_name)
    blob = zf.read(os.path.join(prefix, src["buffers"][0]["uri"]) if prefix else src["buffers"][0]["uri"])

    def read(index):
        a = src["accessors"][index]
        v = src["bufferViews"][a["bufferView"]]
        n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a["componentType"]]
        size = n * np.dtype(dt).itemsize
        stride = v.get("byteStride", 0) or size
        off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        raw = np.frombuffer(blob, np.uint8, (a["count"] - 1) * stride + size, off)
        rows = np.lib.stride_tricks.as_strided(raw, (a["count"], size), (stride, 1))
        return np.ascontiguousarray(rows).view(dt).reshape(a["count"], n)

    world = {}

    def walk(i, parent):
        node = src["nodes"][i]
        m = np.array(node.get("matrix", np.eye(4).flatten()), dtype=np.float64).reshape(4, 4).T
        world[i] = parent @ m
        for c in node.get("children", []):
            walk(c, world[i])
    walk(0, np.eye(4))
    parts = {}  # part name -> (positions, normals, uvs, indices) in model units
    for i, node in enumerate(src["nodes"]):
        for c in node.get("children", []):
            if "mesh" in src["nodes"][c]:
                prim = src["meshes"][src["nodes"][c]["mesh"]]["primitives"][0]
                m = world[c]
                pos = read(prim["attributes"]["POSITION"]).astype(np.float64)
                nrm = read(prim["attributes"]["NORMAL"]).astype(np.float64)
                pos = (m @ np.c_[pos, np.ones(len(pos))].T).T[:, :3]
                nrm = (np.linalg.inv(m[:3, :3]).T @ nrm.T).T
                nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
                uv = read(prim["attributes"]["TEXCOORD_0"]).astype(np.float32)
                idx = read(prim["indices"]).astype(np.uint32).flatten()
                parts[node["name"]] = (pos, nrm, uv, idx)
    body_pos = parts["f_1_main_low"][0]
    centre = (body_pos.min(0) + body_pos.max(0)) / 2.0
    scale = F1_DIAMETER_M / (body_pos[:, 0].max() - body_pos[:, 0].min())

    out_dir = os.path.join(DST, "f1_grenade")
    os.makedirs(os.path.join(out_dir, "textures"), exist_ok=True)
    binary = bytearray()
    gltf = {"asset": {"version": "2.0", "generator": "tools/import_weapons.py --f1"}, "scene": 0,
            "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "accessors": [], "bufferViews": []}

    def add_view(arr, target):
        while len(binary) % 4:
            binary.append(0)
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": arr.nbytes, "target": target})
        binary.extend(arr.tobytes())
        return len(gltf["bufferViews"]) - 1

    def add_acc(arr, kind, target, minmax=False):
        a = {"bufferView": add_view(arr, target), "componentType": 5125 if arr.dtype == np.uint32 else 5126,
             "count": len(arr), "type": kind}
        if minmax:
            a["min"] = arr.min(0).tolist()
            a["max"] = arr.max(0).tolist()
        gltf["accessors"].append(a)
        return len(gltf["accessors"]) - 1

    total = 0
    for part, names in F1_PARTS.items():
        P, N, U, I = [], [], [], []
        base = 0
        for name in names:
            pos, nrm, uv, idx = parts[name]
            pos_m = ((pos - centre) * scale).astype(np.float32)
            dest = np.zeros(len(idx), dtype=np.uint32)
            count = mo.simplify(dest, idx, pos_m, target_index_count=F1_TARGET_TRIS[name] * 3, target_error=0.02)
            used = np.unique(dest[:count])
            remap = np.full(len(pos_m), -1, dtype=np.int64)
            remap[used] = np.arange(len(used))
            P.append(pos_m[used]); N.append(nrm[used].astype(np.float32)); U.append(uv[used])
            I.append((remap[dest[:count]] + base).astype(np.uint32))
            base += len(used)
        P, N, U, I = np.concatenate(P), np.concatenate(N), np.concatenate(U), np.concatenate(I)
        total += len(I) // 3
        prim = {"attributes": {"POSITION": add_acc(P, "VEC3", 34962, True), "NORMAL": add_acc(N, "VEC3", 34962),
                               "TEXCOORD_0": add_acc(U, "VEC2", 34962)},
                "indices": add_acc(I, "SCALAR", 34963), "material": 0}
        gltf["meshes"].append({"name": part, "primitives": [prim]})
        gltf["nodes"].append({"name": part, "mesh": len(gltf["meshes"]) - 1})
        gltf["scenes"][0]["nodes"].append(len(gltf["nodes"]) - 1)
    with open(os.path.join(out_dir, "scene.bin"), "wb") as f:
        f.write(binary)
    gltf["buffers"] = [{"uri": "scene.bin", "byteLength": len(binary)}]
    images = []
    for image in src["images"]:
        uri = image["uri"]
        if "baseColor" in uri or "normal" in uri:
            data, new_uri = shrink(zf.read(os.path.join(prefix, uri) if prefix else uri), uri, 256)
            with open(os.path.join(out_dir, new_uri), "wb") as f:
                f.write(data)
            images.append(new_uri)
    gltf["images"] = [{"uri": u} for u in images]
    gltf["samplers"] = [{"magFilter": 9729, "minFilter": 9987}]
    gltf["textures"] = [{"source": i, "sampler": 0} for i in range(len(images))]
    colour = next(i for i, u in enumerate(images) if "baseColor" in u)
    normal = next(i for i, u in enumerate(images) if "normal" in u)
    gltf["materials"] = [{"name": "f1_grenade", "normalTexture": {"index": normal},
                          "pbrMetallicRoughness": {"baseColorTexture": {"index": colour},
                                                   "metallicFactor": 0.35, "roughnessFactor": 0.7}}]
    with open(os.path.join(out_dir, "model.gltf"), "w") as f:
        json.dump(gltf, f, indent=1)
    lic = [n for n in zf.namelist() if n.endswith("license.txt")]
    if lic:
        with open(os.path.join(out_dir, "license.txt"), "wb") as f:
            f.write(zf.read(lic[0]))
    size = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(out_dir) for fn in fns)
    print(f"{F1_ZIP} -> {os.path.relpath(out_dir, ROOT)}/  ({total} triangles, {size / 1e3:.0f} kB)")


def main() -> None:
    if "--f1" in sys.argv:
        import_f1()
        return
    if "--t26-wheels" in sys.argv:
        bake_t26_wheels(os.path.join(VEHICLES, "t26"))
        return
    for zip_name, (folder, big, small) in MODELS.items():
        path = os.path.join(SRC, zip_name)
        if not os.path.exists(path):
            print("missing", zip_name, "- skipped")
            continue
        vehicle = folder in VEHICLE_FOLDERS
        out_dir = os.path.join(VEHICLES if vehicle else DST, folder)
        os.makedirs(os.path.join(out_dir, "textures"), exist_ok=True)
        zf = zipfile.ZipFile(path)
        gltf_name = next(n for n in zf.namelist() if n.endswith(".gltf"))
        gltf = json.loads(zf.read(gltf_name))
        prefix = os.path.dirname(gltf_name)
        for buf in gltf.get("buffers", []):
            data = zf.read(os.path.join(prefix, buf["uri"]) if prefix else buf["uri"])
            with open(os.path.join(out_dir, buf["uri"]), "wb") as f:
                f.write(data)
        if vehicle:
            drop_specular(gltf)
        for image in gltf.get("images", []):
            uri = image["uri"]
            data = zf.read(os.path.join(prefix, uri) if prefix else uri)
            limit = big if ("baseColor" in uri or "normal" in uri) else small
            new_data, new_uri = shrink(data, uri, limit)
            image["uri"] = new_uri
            with open(os.path.join(out_dir, new_uri), "wb") as f:
                f.write(new_data)
        with open(os.path.join(out_dir, "model.gltf"), "w") as f:
            json.dump(gltf, f, indent=1)
        if folder == "t26":
            bake_t26_wheels(out_dir)
        lic = [n for n in zf.namelist() if n.endswith("license.txt")]
        if lic:
            with open(os.path.join(out_dir, "license.txt"), "wb") as f:
                f.write(zf.read(lic[0]))
        size = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(out_dir) for fn in fns)
        print(f"{zip_name} -> {os.path.relpath(out_dir, ROOT)}/  ({size / 1e6:.1f} MB)")
    import_f1()


if __name__ == "__main__":
    main()
