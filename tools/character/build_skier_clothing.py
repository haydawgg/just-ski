"""Add skinned clothing shells over the partitioned skier body regions.

Run after rebuild_skier_body_materials.py. The tool reads the existing
Outfit_* primitives, duplicates the Jacket/Pants/Gloves triangle groups into
offset shell meshes, and appends them as additional skinned primitives of the
same mesh node. Shell vertices copy JOINTS_0/WEIGHTS_0 verbatim from the body
vertex they clone, so clothing deforms identically to the body by construction.
The skeleton, inverse bind matrices, nodes, and original surfaces are untouched.
"""

from __future__ import annotations

import hashlib
import heapq
import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GLB_PATH = ROOT / "assets" / "characters" / "skier" / "skier_body.glb"
MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963

SHELL_REGIONS = ("Jacket", "Pants", "Gloves")
SHELL_RAMP_METERS = {"Jacket": 0.09, "Pants": 0.07, "Gloves": 0.03}
HAND_MARKERS = ("hand", "f_index", "f_middle", "f_pinky", "f_ring", "thumb")
TORSO_JOINTS = {"spine", "spine.001", "spine.002", "spine.003", "spine.004", "spine.005"}
JACKET_COVER_BAND_MIN_Y = 0.16
JACKET_COLLAR_Y = 0.62
# Collar overlap skirt: jacket shell triangles extend past the material cut up
# to this height with a guaranteed minimum offset, forming a turtleneck lip
# over the skin. Without it the shell tapers to zero exactly at the cut and
# neck flexion opens a skin ring / T-junction crack.
COLLAR_SKIRT_TOP_Y = 0.655
COLLAR_SKIRT_MIN_OFFSET = 0.012
BONE_OFFSETS = {
    "Jacket": {
        # Slimmed insulated volume to match narrower arms: still reads as a
        # garment, not paint, without Michelin-man sleeves.
        "upper_arm.L": 0.028, "upper_arm.R": 0.028,
        "forearm.L": 0.024, "forearm.R": 0.024,
        "shoulder.L": 0.028, "shoulder.R": 0.028,
        "spine.003": 0.027, "spine.002": 0.027,
        "spine.001": 0.029, "spine": 0.030,
    },
    "Pants": {
        # Slimmed ski pants taper toward the boot.
        "thigh.L": 0.018, "thigh.R": 0.018,
        "shin.L": 0.014, "shin.R": 0.014,
        "pelvis.L": 0.020, "pelvis.R": 0.020,
    },
    "Gloves": {
        "hand.L": 0.018, "hand.R": 0.018,
    },
}
DEFAULT_OFFSETS = {"Jacket": 0.027, "Pants": 0.022, "Gloves": 0.010}


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


def region_of_material(doc: dict, material_index) -> str:
    return doc["materials"][material_index]["name"].removeprefix("Outfit_")


def normalize(value: tuple) -> tuple:
    length = (value[0] ** 2 + value[1] ** 2 + value[2] ** 2) ** 0.5
    if length < 1e-9:
        return (0.0, 1.0, 0.0)
    return (value[0] / length, value[1] / length, value[2] / length)


def taper(distance: float, ramp: float) -> float:
    t = min(1.0, distance / ramp)
    return t * t * (3.0 - 2.0 * t)


def geodesic_distances(shell_vertices: list, adjacency: dict, source_positions: list, border: set) -> dict:
    start = [(0.0, v) for v in border]
    heapq.heapify(start)
    distances = {v: math.inf for v in shell_vertices}
    for v in border:
        distances[v] = 0.0
    settled: set[int] = set()
    while start:
        distance, vertex = heapq.heappop(start)
        if vertex in settled:
            continue
        settled.add(vertex)
        for neighbor in adjacency[vertex]:
            step = math.dist(source_positions[vertex], source_positions[neighbor])
            candidate = distance + step
            if candidate < distances[neighbor]:
                distances[neighbor] = candidate
                heapq.heappush(start, (candidate, neighbor))
    return distances


def dominant_joint(triangle: tuple, joints: list, weights: list, names: list) -> str:
    score = {}
    for vertex in triangle:
        for joint, weight in zip(joints[vertex], weights[vertex]):
            score[names[joint]] = score.get(names[joint], 0.0) + weight
    return max(score, key=score.get)


def is_hand_joint(name: str) -> bool:
    return any(marker in name for marker in HAND_MARKERS)


def main() -> None:
    raw = GLB_PATH.read_bytes()
    magic, version, _length = struct.unpack_from("<III", raw, 0)
    if magic != MAGIC or version != 2:
        raise RuntimeError("Expected a glTF 2.0 binary")
    json_length, json_type = struct.unpack_from("<II", raw, 12)
    if json_type != JSON_CHUNK:
        raise RuntimeError("Missing GLB JSON chunk")
    json_start = 20
    doc = json.loads(raw[json_start : json_start + json_length])
    bin_header = json_start + json_length
    bin_length, bin_type = struct.unpack_from("<II", raw, bin_header)
    if bin_type != BIN_CHUNK:
        raise RuntimeError("Missing GLB binary chunk")
    binary = bytearray(raw[bin_header + 8 : bin_header + 8 + bin_length])

    extras = doc.get("extras") or {}
    if extras.get("clothingShells"):
        raise RuntimeError("Clothing shells already present; rebuild from the pristine source first")
    mesh = doc["meshes"][0]
    region_primitives = {region_of_material(doc, p["material"]): p for p in mesh["primitives"]}
    missing = [region for region in SHELL_REGIONS if region not in region_primitives]
    if missing:
        raise RuntimeError(f"Missing Outfit_ regions for shells: {missing}")

    positions = read_accessor(doc, binary, mesh["primitives"][0]["attributes"]["POSITION"])
    normals = read_accessor(doc, binary, mesh["primitives"][0]["attributes"]["NORMAL"])
    joints = read_accessor(doc, binary, mesh["primitives"][0]["attributes"]["JOINTS_0"])
    weights = read_accessor(doc, binary, mesh["primitives"][0]["attributes"]["WEIGHTS_0"])
    joint_names = [doc["nodes"][node].get("name", "") for node in doc["skins"][0]["joints"]]

    vertex_regions: dict[int, set[str]] = {}
    region_triangles: dict[str, list[tuple[int, int, int]]] = {}
    for primitive in mesh["primitives"]:
        region = region_of_material(doc, primitive["material"])
        indices = read_accessor(doc, binary, primitive["indices"])
        triangles = [tuple(indices[o : o + 3]) for o in range(0, len(indices), 3)]
        region_triangles[region] = triangles
        for triangle in triangles:
            for vertex in triangle:
                vertex_regions.setdefault(vertex, set()).add(region)

    for region in SHELL_REGIONS:
        candidates = []
        cut_verts: set[int] = set()
        if region == "Jacket":
            for triangle in region_triangles["Jacket"]:
                dominant = dominant_joint(triangle, joints, weights, joint_names)
                if is_hand_joint(dominant):
                    continue
                if dominant in TORSO_JOINTS and sum(positions[v][1] for v in triangle) / 3.0 > JACKET_COLLAR_Y:
                    cut_verts.update(triangle)
                    continue
                candidates.append(triangle)
            # Collar overlap skirt: torso-joint skin triangles just above the
            # material cut join the Jacket shell, so the shell rides over the
            # seam instead of ending exactly on it. Skinning copies verbatim,
            # so the skirt deforms with the neck.
            skirt_tris = 0
            for triangle in region_triangles["Skin"]:
                dominant = dominant_joint(triangle, joints, weights, joint_names)
                if dominant not in TORSO_JOINTS:
                    continue
                centroid_y = sum(positions[v][1] for v in triangle) / 3.0
                if JACKET_COLLAR_Y < centroid_y <= COLLAR_SKIRT_TOP_Y:
                    candidates.append(triangle)
                    skirt_tris += 1
            if skirt_tris == 0:
                raise RuntimeError("Collar skirt found no torso triangles; cut geometry changed")
            print(f"Jacket collar skirt: {skirt_tris} triangles above y={JACKET_COLLAR_Y}")
            for triangle in region_triangles["Pants"]:
                if sum(positions[v][1] for v in triangle) / 3.0 >= JACKET_COVER_BAND_MIN_Y:
                    candidates.append(triangle)
                    cut_verts.update(v for v in triangle if positions[v][1] < JACKET_COVER_BAND_MIN_Y)
        elif region == "Pants":
            for triangle in region_triangles["Pants"]:
                if sum(positions[v][1] for v in triangle) / 3.0 < JACKET_COVER_BAND_MIN_Y:
                    candidates.append(triangle)
                    cut_verts.update(v for v in triangle if positions[v][1] >= JACKET_COVER_BAND_MIN_Y)
        else:
            candidates = list(region_triangles["Gloves"])
        shell_vertices = sorted({v for triangle in candidates for v in triangle})
        adjacency: dict[int, set[int]] = {v: set() for v in shell_vertices}
        for a, b, c in candidates:
            adjacency[a].update((b, c))
            adjacency[b].update((a, c))
            adjacency[c].update((a, b))
        border = {v for v in shell_vertices if len(vertex_regions[v]) > 1} | (cut_verts & set(shell_vertices))
        distances = geodesic_distances(shell_vertices, adjacency, positions, border)

        ramp = SHELL_RAMP_METERS[region]
        offsets = BONE_OFFSETS[region]
        default_offset = DEFAULT_OFFSETS[region]
        out_positions = []
        out_normals = []
        out_joints = []
        out_weights = []
        for vertex in shell_vertices:
            dominant = joint_names[joints[vertex][max(range(4), key=lambda i: weights[vertex][i])]]
            amount = offsets.get(dominant, default_offset) * taper(distances[vertex], ramp)
            if region == "Jacket" and positions[vertex][1] > JACKET_COLLAR_Y:
                # Skirt zone never tapers shut: the lip stands off the skin.
                amount = max(amount, COLLAR_SKIRT_MIN_OFFSET)
            px, py, pz = positions[vertex]
            nx, ny, nz = normalize(normals[vertex])
            out_positions.append((px + nx * amount, py + ny * amount, pz + nz * amount))
            out_normals.append(normals[vertex])
            out_joints.append(joints[vertex])
            out_weights.append(weights[vertex])
        out_indices = []
        local_index = {vertex: i for i, vertex in enumerate(shell_vertices)}
        for a, b, c in candidates:
            out_indices.extend((local_index[a], local_index[b], local_index[c]))

        def pack(values, fmt: str) -> bytes:
            while len(binary) % 4:
                binary.append(0)
            view_index = len(doc["bufferViews"])
            doc["bufferViews"].append(
                {"buffer": 0, "byteOffset": len(binary), "byteLength": len(values) * struct.calcsize(fmt), "target": ARRAY_BUFFER}
            )
            payload = struct.pack("<" + fmt * len(values), *values)
            binary.extend(payload)
            return view_index

        flat_positions = [c for v in out_positions for c in v]
        flat_normals = [c for v in out_normals for c in v]
        flat_joints = [c for v in out_joints for c in v]
        flat_weights = [c for v in out_weights for c in v]
        position_view = pack(flat_positions, "f")
        normal_view = pack(flat_normals, "f")
        joints_view = pack(flat_joints, "B")
        weights_view = pack(flat_weights, "f")
        while len(binary) % 4:
            binary.append(0)
        indices_view = len(doc["bufferViews"])
        doc["bufferViews"].append(
            {"buffer": 0, "byteOffset": len(binary), "byteLength": len(out_indices) * 2, "target": ELEMENT_ARRAY_BUFFER}
        )
        binary.extend(struct.pack("<" + "H" * len(out_indices), *out_indices))

        def add_accessor(view: int, kind: str, component: int, count: int, min_max=None) -> int:
            accessor = {"bufferView": view, "componentType": component, "count": count, "type": kind}
            if min_max is not None:
                accessor["min"] = min_max[0]
                accessor["max"] = min_max[1]
            index = len(doc["accessors"])
            doc["accessors"].append(accessor)
            return index

        xs = [v[0] for v in out_positions]
        ys = [v[1] for v in out_positions]
        zs = [v[2] for v in out_positions]
        position_accessor = add_accessor(position_view, "VEC3", 5126, len(out_positions), ([min(xs), min(ys), min(zs)], [max(xs), max(ys), max(zs)]))
        normal_accessor = add_accessor(normal_view, "VEC3", 5126, len(out_normals))
        joints_accessor = add_accessor(joints_view, "VEC4", 5121, len(out_joints))
        weights_accessor = add_accessor(weights_view, "VEC4", 5126, len(out_weights))
        indices_accessor = add_accessor(indices_view, "SCALAR", 5123, len(out_indices), ([min(out_indices)], [max(out_indices)]))

        mesh["primitives"].append(
            {
                "attributes": {
                    "POSITION": position_accessor,
                    "NORMAL": normal_accessor,
                    "JOINTS_0": joints_accessor,
                    "WEIGHTS_0": weights_accessor,
                },
                "indices": indices_accessor,
                "material": region_primitives[region]["material"],
                "mode": 4,
            }
        )
        used_amounts = [sum(abs(out_positions[i][k] - positions[v][k]) for k in range(3)) / 3.0 for i, v in enumerate(shell_vertices)]
        print(f"{region} shell: {len(out_indices) // 3} triangles, {len(shell_vertices)} vertices, mean offset {sum(used_amounts) / len(used_amounts):.4f} m")

    extras["clothingShells"] = list(SHELL_REGIONS)
    extras["clothingShellProfile"] = "insulated_skiwear_v2"
    doc["extras"] = extras
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
    digest = hashlib.sha256(output).hexdigest().upper()
    print(f"Wrote {GLB_PATH} ({len(output)} bytes)")
    print(f"SHA-256: {digest}")


if __name__ == "__main__":
    main()
