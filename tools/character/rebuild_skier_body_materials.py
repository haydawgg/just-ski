"""Split the CC0 skier body into stable material regions without changing skinning.

The source GLB has one skinned primitive and no materials. Preserve its skeleton,
bind matrices, and animation data while partitioning triangles by bone groups.
Hem and collar cuts append seam vertices with interpolated, normalized skin weights.
"""

from __future__ import annotations

import json
import struct
import sys
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

    processed = "--from-processed" in sys.argv
    primitives = doc["meshes"][0]["primitives"]
    if not processed and (len(primitives) != 1 or doc.get("materials")):
        raise RuntimeError("Use pristine source, or --from-processed to re-tailor the existing base surfaces")
    primitive = doc["meshes"][0]["primitives"][0]
    joints = read_accessor(doc, binary, primitive["attributes"]["JOINTS_0"])
    weights = read_accessor(doc, binary, primitive["attributes"]["WEIGHTS_0"])
    positions = read_accessor(doc, binary, primitive["attributes"]["POSITION"])
    indices = read_accessor(doc, binary, primitive["indices"])
    if processed:
        if [doc["materials"][p["material"]]["name"] for p in primitives[:5]] != ["Outfit_" + r for r in REGIONS]:
            raise RuntimeError("Expected five named base surfaces before the clothing shells")
        indices = [i for p in primitives[:5] for i in read_accessor(doc, binary, p["indices"])]
        doc.get("extras", {}).pop("clothingShells", None)
    joint_nodes = doc["skins"][0]["joints"]
    joint_names = [doc["nodes"][node].get("name", "") for node in joint_nodes]
    # Split crossing torso triangles at the garment seams. Classifying whole
    # triangles by centroid leaves a sawtooth hem that grows during flexion.
    attributes = {name: list(read_accessor(doc, binary, accessor)) for name, accessor in primitive["attributes"].items()}
    split_cache = {}

    def intersection(a, b, plane):
        key = (min(a, b), max(a, b), plane)
        if key in split_cache:
            return split_cache[key]
        pa, pb = attributes["POSITION"][a], attributes["POSITION"][b]
        t = (plane - pa[1]) / (pb[1] - pa[1])
        if t < 1e-6:
            return a
        if t > 1 - 1e-6:
            return b
        index = len(attributes["POSITION"])
        influences = {}
        for source, blend in ((a, 1-t), (b, t)):
            for joint, weight in zip(attributes["JOINTS_0"][source], attributes["WEIGHTS_0"][source]):
                influences[joint] = influences.get(joint, 0) + weight * blend
        ranked = sorted(influences.items(), key=lambda entry: (-entry[1], entry[0]))[:4]
        ranked += [(0, 0)] * (4-len(ranked))
        total = sum(w for _, w in ranked)
        for name, rows in attributes.items():
            if name == "JOINTS_0":
                value = tuple(j for j, _ in ranked)
            elif name == "WEIGHTS_0":
                value = tuple(w/total for _, w in ranked)
            else:
                value = tuple(x + (y-x)*t for x, y in zip(rows[a], rows[b]))
                if name == "POSITION":
                    value = (value[0], plane, value[2])
                elif name == "NORMAL":
                    length = sum(v*v for v in value)**0.5
                    value = tuple(v/max(length, 1e-9) for v in value)
            rows.append(value)
        split_cache[key] = index
        return index

    def clip(polygon, plane, upper):
        result = []
        for a, b in zip(polygon, polygon[1:] + polygon[:1]):
            inside_a = (attributes["POSITION"][a][1] >= plane) == upper
            inside_b = (attributes["POSITION"][b][1] >= plane) == upper
            if inside_a:
                result.append(a)
            if inside_a != inside_b:
                result.append(intersection(a, b, plane))
        return list(dict.fromkeys(result))

    grouped: dict[str, list[int]] = {region: [] for region in REGIONS}
    for offset in range(0, len(indices), 3):
        triangle = indices[offset : offset + 3]
        winner = region_for_triangle(triangle, joints, weights, positions, joint_names)
        score = {}
        for v in triangle:
            for j, w in zip(joints[v], weights[v]):
                score[joint_names[j]] = score.get(joint_names[j], 0) + w
        dominant = max(score, key=score.get)
        torso = dominant in TORSO_JOINTS or dominant.startswith(("pelvis", "thigh"))
        if not torso:
            grouped[winner].extend(triangle)
            continue
        polygons = [triangle]
        for plane in (JACKET_HEM_Y, JACKET_COLLAR_Y):
            divided = []
            for polygon in polygons:
                for upper in (False, True):
                    part = clip(polygon, plane, upper)
                    if len(part) >= 3:
                        divided.append(part)
            polygons = divided
        for polygon in polygons:
            y = sum(attributes["POSITION"][v][1] for v in polygon)/len(polygon)
            region = "Pants" if y < JACKET_HEM_Y else "Skin" if y > JACKET_COLLAR_Y else "Jacket"
            for i in range(1, len(polygon)-1):
                grouped[region].extend((polygon[0], polygon[i], polygon[i+1]))

    new_attributes = {}
    for name, rows in attributes.items():
        original = doc["accessors"][primitive["attributes"][name]]
        component = original["componentType"]
        fmt = {5121: "B", 5123: "H", 5126: "f"}[component]
        while len(binary) % 4:
            binary.append(0)
        payload = struct.pack("<" + fmt * sum(len(r) for r in rows), *(v for r in rows for v in r))
        view = len(doc["bufferViews"])
        doc["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(payload), "target": 34962})
        binary.extend(payload)
        accessor = {"bufferView": view, "componentType": component, "count": len(rows), "type": original["type"]}
        if name == "POSITION":
            accessor["min"] = [min(r[i] for r in rows) for i in range(3)]
            accessor["max"] = [max(r[i] for r in rows) for i in range(3)]
        new_attributes[name] = len(doc["accessors"])
        doc["accessors"].append(accessor)
    primitive["attributes"] = new_attributes

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
