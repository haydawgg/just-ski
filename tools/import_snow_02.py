"""Download and pack the exact CC0 Snow 02 maps used by Summit Sessions."""

from __future__ import annotations

import hashlib
import shutil
import tempfile
import urllib.request
from pathlib import Path

from PIL import Image


ASSETS = {
    "diffuse": (
        "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/snow_02/snow_02_diff_2k.jpg",
        "5541e5601951b071691238ddc70632c0",
    ),
    "normal_gl": (
        "https://dl.polyhaven.org/file/ph-assets/Textures/png/2k/snow_02/snow_02_nor_gl_2k.png",
        "3c07c791818404722c924b951c5eb841",
    ),
    "roughness": (
        "https://dl.polyhaven.org/file/ph-assets/Textures/png/2k/snow_02/snow_02_rough_2k.png",
        "315f17fbf6cd4573fb500f9a83f5e899",
    ),
    "translucency": (
        "https://dl.polyhaven.org/file/ph-assets/Textures/png/2k/snow_02/snow_02_translucent_2k.png",
        "cff375b8843c5fcfd801c3a755e3725f",
    ),
}

EXPECTED_SIZE = (2048, 2048)
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "materials" / "snow_02"


def download(name: str, url: str, expected_md5: str, directory: Path) -> Path:
    suffix = Path(url).suffix
    target = directory / f"{name}{suffix}"
    request = urllib.request.Request(url, headers={"User-Agent": "SummitSessionsAssetImport/1.0"})
    with urllib.request.urlopen(request) as response, target.open("wb") as output:
        shutil.copyfileobj(response, output)
    digest = hashlib.md5(target.read_bytes()).hexdigest()
    if digest != expected_md5:
        raise RuntimeError(f"Checksum mismatch for {name}: {digest}")
    return target


def require_2k(image: Image.Image, label: str) -> None:
    if image.size != EXPECTED_SIZE:
        raise RuntimeError(f"{label} must be 2048x2048, got {image.size}")


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="summit-snow-02-") as temporary:
        temporary_dir = Path(temporary)
        sources = {
            name: download(name, url, digest, temporary_dir)
            for name, (url, digest) in ASSETS.items()
        }

        diffuse_output = OUTPUT_DIR / "snow_02_diff_2k.jpg"
        shutil.copyfile(sources["diffuse"], diffuse_output)

        with (
            Image.open(sources["normal_gl"]) as normal_source,
            Image.open(sources["roughness"]) as roughness_source,
            Image.open(sources["translucency"]) as translucency_source,
        ):
            normal = normal_source.convert("RGB")
            roughness = roughness_source.convert("L")
            translucency = translucency_source.convert("L")
            require_2k(normal, "OpenGL normal")
            require_2k(roughness, "roughness")
            require_2k(translucency, "translucency")
            normal_x, normal_y, _normal_z = normal.split()
            packed = Image.merge("RGBA", (normal_x, normal_y, roughness, translucency))
            packed.save(OUTPUT_DIR / "snow_02_detail_2k.png", optimize=True)

        with Image.open(diffuse_output) as diffuse:
            require_2k(diffuse, "diffuse")

    print(f"Imported Snow 02 textures into {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
