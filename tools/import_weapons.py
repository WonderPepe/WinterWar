"""Unpacks the downloaded weapon and vehicle models (assets_source/*.zip, glTF from Sketchfab) into
assets/models/weapons/<name>/ (vehicles: assets/models/vehicles/<name>/) and shrinks their textures so the web download stays small.
Not part of the game. Run from the project folder:  python3 tools/import_weapons.py
Needs Pillow.
"""
import io
import json
import os
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


def main() -> None:
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
        lic = [n for n in zf.namelist() if n.endswith("license.txt")]
        if lic:
            with open(os.path.join(out_dir, "license.txt"), "wb") as f:
                f.write(zf.read(lic[0]))
        size = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(out_dir) for fn in fns)
        print(f"{zip_name} -> {os.path.relpath(out_dir, ROOT)}/  ({size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
