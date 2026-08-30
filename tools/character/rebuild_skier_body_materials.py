"""Split the CC0 skier body into stable material regions without changing skinning.

The source GLB has one skinned primitive and no materials. This script retains its
vertex buffers, nodes, skeleton, inverse bind matrices, and skin weights verbatim,
then partitions only the triangle index stream according to weighted bone groups.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GLB_PATH = ROOT / "assets" / "characters" / "skier" / "skier_body.glb"
MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
REGIONS = ("Jacket", "Pants", "Skin", "Gloves", "BootUnderlay")
HAND_MARKERS = ("hand", "f_index", "f_middle", "f_pinky", "f_ring", "thumb")
TORSO_JOINTS = {"spine", "spine.001", "spine.002", "spine.003", "spine.004", "spine.005"}
JACKET_HEM_Y = 0.16
JACKET_COLLAR_Y = 0.62


def read_accessor(doc: dict, binary: bytes, accessor_index: int) -> list:
    accessor = doc["accessors"][accessor_index]
    view = doc["bufferViews"][accessor["bufferView"]]
    component = accessor["componentType"]
    widths = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
    fmt, size = widths[component]
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
    stride = view.get("byteStride", size * components)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    values = []
    for row in range(accessor["count"]):
        unpacked = struct.unpack_from("<" + fmt * components, binary, start + row * stride)
        values.append(unpacked[0] if components == 1 else unpacked)
    return values


def region_for_joint(name: str) -> str:
    lowered = name.lower()
    if any(token in lowered for token in ("hand", "finger", "thumb")):
        return "Gloves"
    if any(token in lowered for token in ("foot", "toe", "heel")):
        return "BootUnderlay"
    if any(token in lowered for token in ("pelvis.", "thigh", "shin")):
        return "Pants"
    if name in {"spine.004", "spine.005"}:
        return "Skin"
    return "Jacket"


def region_for_triangle(triangle, joints, weights, positions, joint_names) -> str:
    score = {}
    for vertex in triangle:
        for joint, weight in zip(joints[vertex], weights[vertex]):
            score[joint_names[joint]] = score.get(joint_names[joint], 0.0) + weight
    dominant = max(score, key=score.get)
    lowered = dominant.lower()
    if any(marker in lowered for marker in HAND_MARKERS):
        return "Gloves"
    if dominant in TORSO_JOINTS:
        centroid_y = sum(positions[v][1] for v in triangle) / 3.0
        if centroid_y > JACKET_COLLAR_Y:
            return "Skin"
        if centroid_y < JACKET_HEM_Y:
            return "Pants"
    return region_for_joint(dominant)


def main() -> None:
    raw = GLB_PATH.read_bytes()
    magic, version, _length = struct.unpack_from("<III", raw, 0)
    if magic != MAGIC or version != 2:
        raise RuntimeError("Expected a glTF 2.0 binary")
    json_length, json_type = struct.unpack_from("<II", raw, 12)
    if json_type != JSON_CHUNK:
        raise RuntimeError("Missing GLB JSON chunk")
    json_start = 20
    doc = json.loads(raw[json_start : json_start + json_length].decode("utf-8"))
    bin_header = json_start + json_length
    bin_length, bin_type = struct.unpack_from("<II", raw, bin_header)
    if bin_type != BIN_CHUNK:
        raise RuntimeError("Missing GLB binary chunk")
    binary = bytearray(raw[bin_header + 8 : bin_header + 8 + bin_length])

    if len(doc["meshes"][0]["primitives"]) != 1 or doc.get("materials"):
        raise RuntimeError("Expected the untouched one-primitive, no-material source GLB")
    primitive = doc["meshes"][0]["primitives"][0]
    joints = read_accessor(doc, binary, primitive["attributes"]["JOINTS_0"])
    weights = read_accessor(doc, binary, primitive["attributes"]["WEIGHTS_0"])
    positions = read_accessor(doc, binary, primitive["attributes"]["POSITION"])
    indices = read_accessor(doc, binary, primitive["indices"])
    joint_nodes = doc["skins"][0]["joints"]
    joint_names = [doc["nodes"][node].get("name", "") for node in joint_nodes]
    grouped: dict[str, list[int]] = {region: [] for region in REGIONS}
    for offset in range(0, len(indices), 3):
        triangle = indices[offset : offset + 3]
        winner = region_for_triangle(triangle, joints, weights, positions, joint_names)
        grouped[winner].extend(triangle)

    doc["materials"] = []
    for region in REGIONS:
        doc["materials"].append(
            {
                "name": "Outfit_" + region,
                "pbrMetallicRoughness": {
                    "baseColorFactor": [0.5, 0.5, 0.5, 1.0],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.8,
                },
            }
        )

    new_primitives = []
    for material_index, region in enumerate(REGIONS):
        values = grouped[region]
        while len(binary) % 4:
            binary.append(0)
        byte_offset = len(binary)
        binary.extend(struct.pack("<" + "H" * len(values), *values))
        view_index = len(doc["bufferViews"])
        doc["bufferViews"].append(
            {"buffer": 0, "byteOffset": byte_offset, "byteLength": len(values) * 2, "target": 34963}
        )
        accessor_index = len(doc["accessors"])
        doc["accessors"].append(
            {
                "bufferView": view_index,
                "componentType": 5123,
                "count": len(values),
                "type": "SCALAR",
                "min": [min(values)],
                "max": [max(values)],
            }
        )
        new_primitives.append(
            {
                "attributes": primitive["attributes"],
                "indices": accessor_index,
                "material": material_index,
                "mode": primitive.get("mode", 4),
            }
        )
        print(f"{region}: {len(values) // 3} triangles")
    doc["meshes"][0]["primitives"] = new_primitives
    doc["buffers"][0]["byteLength"] = len(binary)

    json_bytes = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    binary += b"\0" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(json_bytes) + 8 + len(binary)
    output = bytearray(struct.pack("<III", MAGIC, 2, total))
    output.extend(struct.pack("<II", len(json_bytes), JSON_CHUNK))
    output.extend(json_bytes)
    output.extend(struct.pack("<II", len(binary), BIN_CHUNK))
    output.extend(binary)
    GLB_PATH.write_bytes(output)
    print(f"Wrote {GLB_PATH} ({len(output)} bytes)")


if __name__ == "__main__":
    main()
