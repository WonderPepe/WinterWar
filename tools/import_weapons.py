"""Unpacks the downloaded weapon models (assets_source/*.zip, glTF from Sketchfab) into
assets/models/weapons/<name>/ and shrinks their textures so the web download stays small.
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

# zip file -> (folder name, max texture size for colour/normal maps, max size for the rest)
MODELS = {
    "mosin_nagant_m91.zip": ("mosin", 1024, 512),
    "suomi_kp-31.zip": ("suomi", 1024, 512),
    "machine_gun_maxim.zip": ("maxim", 512, 512),
}


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


def main() -> None:
    for zip_name, (folder, big, small) in MODELS.items():
        path = os.path.join(SRC, zip_name)
        if not os.path.exists(path):
            print("missing", zip_name, "- skipped")
            continue
        out_dir = os.path.join(DST, folder)
        os.makedirs(os.path.join(out_dir, "textures"), exist_ok=True)
        zf = zipfile.ZipFile(path)
        gltf_name = next(n for n in zf.namelist() if n.endswith(".gltf"))
        gltf = json.loads(zf.read(gltf_name))
        prefix = os.path.dirname(gltf_name)
        for buf in gltf.get("buffers", []):
            data = zf.read(os.path.join(prefix, buf["uri"]) if prefix else buf["uri"])
            with open(os.path.join(out_dir, buf["uri"]), "wb") as f:
                f.write(data)
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
        print(f"{zip_name} -> assets/models/weapons/{folder}/  ({size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
