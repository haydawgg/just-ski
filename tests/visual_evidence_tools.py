"""Build and validate the Codex-facing visual evidence bundle.

Godot owns capture timing and semantic telemetry.  This small post-processor
owns the cross-process run index, image comparison, contact sheets, and the
human-readable report so the app has one predictable place to start reviewing.
"""

from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
import math
import os
import shutil
import sys
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps, ImageStat


SCHEMA_VERSION = "visual-evidence-v1"
VALID_STATUSES = {"pass", "fail", "advisory", "review_required", "not_comparable", "missing"}
DEFAULT_THRESHOLDS = {"mean_abs_delta": 0.03, "changed_fraction": 0.10, "pixel_tolerance": 8}
DEFAULT_CAPTURE_SIZE = (1280, 720)
COMPATIBILITY_KEYS = (
    "godot_version", "renderer", "gpu", "video_adapter", "capture_width",
    "capture_height", "environment", "preset", "render_scale", "fixed_fps",
)


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"JSON object expected: {path}")
    return value


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")


def safe_name(value: str) -> str:
    result = "".join(character.lower() if character.isalnum() else "_" for character in value)
    return result.strip("_") or "artifact"


def relative_posix(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def as_json_value(value: Any) -> Any:
    if isinstance(value, Path):
        return value.as_posix()
    if isinstance(value, dict):
        return {str(key): as_json_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [as_json_value(item) for item in value]
    return value


def load_catalog(repo_root: Path) -> dict[str, Any]:
    path = repo_root / "tests" / "visual_scenarios.json"
    return read_json(path) if path.is_file() else {"scenarios": [], "templates": []}


def catalog_index(catalog: dict[str, Any]) -> dict[str, dict[str, Any]]:
    index: dict[str, dict[str, Any]] = {}
    for entry in catalog.get("scenarios", []):
        if isinstance(entry, dict) and entry.get("id"):
            index[str(entry["id"])] = entry
    return index


def catalog_entry(catalog: dict[str, Any], scenario_id: str) -> dict[str, Any] | None:
    exact = catalog_index(catalog).get(scenario_id)
    if exact is not None:
        return exact
    for entry in catalog.get("templates", []):
        if not isinstance(entry, dict):
            continue
        prefix = str(entry.get("id_prefix", ""))
        if prefix and scenario_id.startswith(prefix):
            return entry
    return None


def validate_catalog(catalog: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if catalog.get("schema_version") != "visual-scenarios-v1":
        errors.append("scenario catalog schema_version must equal visual-scenarios-v1")
    capture_size = catalog.get("capture_size", {})
    if not isinstance(capture_size, dict) or int(capture_size.get("width", 0)) <= 0 or int(capture_size.get("height", 0)) <= 0:
        errors.append("scenario catalog capture_size must contain positive width and height")
    scenario_entries = [entry for entry in catalog.get("scenarios", []) if isinstance(entry, dict)]
    ids = [str(entry.get("id", "")) for entry in scenario_entries]
    errors.extend(f"duplicate scenario id: {identifier}" for identifier, count in Counter(ids).items() if identifier and count > 1)
    required = ["id", "suite", "label", "state", "phase", "view", "capture_key", "required_artifacts", "roi", "masks", "capture_timing", "semantic_checks", "human_review"]
    for entry in scenario_entries:
        identifier = str(entry.get("id", "<missing>"))
        errors.extend(f"scenario {identifier} missing {key}" for key in required if key not in entry)
        roi = entry.get("roi")
        if not isinstance(roi, dict) or roi.get("type") != "normalized_rect":
            errors.append(f"scenario {identifier} roi must be a normalized_rect object")
        elif any(not isinstance(roi.get(key), (int, float)) for key in ["x", "y", "width", "height"]):
            errors.append(f"scenario {identifier} roi must contain numeric x/y/width/height")
        if not isinstance(entry.get("masks"), list):
            errors.append(f"scenario {identifier} masks must be an array")
        if not isinstance(entry.get("required_artifacts"), list) or not entry.get("required_artifacts"):
            errors.append(f"scenario {identifier} required_artifacts must be a non-empty array")
    for entry in catalog.get("templates", []):
        if not isinstance(entry, dict) or not str(entry.get("id_prefix", "")):
            errors.append("every scenario template must define a non-empty id_prefix")
    return errors


def merge_context(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    result = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge_context(result[key], value)
        else:
            result[key] = value
    return result


def discover_suite_manifests(bundle: Path) -> list[Path]:
    suites = bundle / "suites"
    if not suites.is_dir():
        return []
    return sorted(path for path in suites.rglob("visual_run.json") if path.is_file())


def suite_context(manifest: dict[str, Any]) -> dict[str, Any]:
    context = manifest.get("context", {})
    return context if isinstance(context, dict) else {}


def merge_suite_manifests(bundle: Path, manifests: Iterable[Path], catalog: dict[str, Any]) -> dict[str, Any]:
    scenarios: list[dict[str, Any]] = []
    artifacts: list[dict[str, Any]] = []
    telemetry: list[dict[str, Any]] = []
    checks: list[dict[str, Any]] = []
    review_items: list[dict[str, Any]] = []
    errors: list[str] = []
    suite_summaries: list[dict[str, Any]] = []

    for manifest_path in manifests:
        manifest = read_json(manifest_path)
        suite_relative = relative_posix(manifest_path.parent, bundle)
        context = suite_context(manifest)
        suite = str(manifest.get("suite", context.get("suite_id", "unknown")))
        variant = safe_name(suite_relative.removeprefix("suites/"))
        scenario_id_map: dict[str, str] = {}
        for raw_scenario in manifest.get("scenarios", []):
            if not isinstance(raw_scenario, dict):
                continue
            scenario = json.loads(json.dumps(raw_scenario))
            stable_id = str(scenario.get("id", "unknown"))
            instance_id = f"{stable_id}@{variant}"
            scenario_id_map[stable_id] = instance_id
            scenario["stable_id"] = stable_id
            scenario["instance_id"] = instance_id
            scenario["suite_manifest"] = suite_relative
            scenario["variant"] = variant
            scenario["context"] = context
            scenarios.append(scenario)
            for prompt in scenario.get("human_review", []):
                review_items.append({
                    "id": f"{instance_id}:{prompt}",
                    "scenario_id": instance_id,
                    "prompt": prompt,
                    "status": "needs_review",
                })

        local_artifacts = manifest.get("artifacts", [])
        for raw_artifact in local_artifacts:
            if not isinstance(raw_artifact, dict):
                continue
            artifact = json.loads(json.dumps(raw_artifact))
            local_path = Path(str(artifact.get("path", "")))
            artifact["path"] = (Path(suite_relative) / local_path).as_posix()
            artifact["suite_manifest"] = suite_relative
            artifact["variant"] = variant
            artifact["id"] = f"{artifact.get('id', 'artifact')}@{variant}"
            artifact["scenario_instance_id"] = scenario_id_map.get(str(artifact.get("scenario_id", "")), f"{artifact.get('scenario_id', 'unknown')}@{variant}")
            artifact["scenario_id"] = str(artifact.get("scenario_id", "unknown"))
            artifact["context"] = merge_context(context, artifact.get("metadata", {}))
            artifacts.append(artifact)

        for raw_telemetry in manifest.get("telemetry", []):
            if not isinstance(raw_telemetry, dict):
                continue
            entry = json.loads(json.dumps(raw_telemetry))
            entry["path"] = (Path(suite_relative) / Path(str(entry.get("path", "")))).as_posix()
            entry["scenario_instance_id"] = scenario_id_map.get(str(entry.get("scenario_id", "")), f"{entry.get('scenario_id', 'unknown')}@{variant}")
            telemetry.append(entry)

        for raw_check in manifest.get("checks", []):
            if isinstance(raw_check, dict):
                check = json.loads(json.dumps(raw_check))
                check["suite_manifest"] = suite_relative
                check["id"] = f"{check.get('id', 'check')}@{variant}"
                checks.append(check)
        for raw_review in manifest.get("review_items", []):
            if isinstance(raw_review, dict):
                item = json.loads(json.dumps(raw_review))
                local_scenario_id = str(item.get("scenario_id", "unknown"))
                instance_id = scenario_id_map.get(local_scenario_id, f"{local_scenario_id}@{variant}")
                prompt = str(item.get("prompt", ""))
                item["scenario_id"] = instance_id
                item["id"] = f"{instance_id}:{prompt}"
                item["suite_manifest"] = suite_relative
                review_items.append(item)
        errors.extend(str(error) for error in manifest.get("errors", []))
        suite_summaries.append({
            "suite": suite,
            "variant": variant,
            "manifest": suite_relative,
            "status": manifest.get("status", "missing"),
            "exit_code": manifest.get("exit_code", 1),
            "context": context,
        })

    for scenario in scenarios:
        catalog_definition = catalog_entry(catalog, str(scenario.get("stable_id", "")))
        if catalog_definition:
            merged = dict(catalog.get("defaults", {}))
            merged.update(catalog_definition)
            merged.update(scenario)
            scenario.clear()
            scenario.update(merged)

    context_path = bundle / "run_context.json"
    root_context = read_json(context_path) if context_path.is_file() else {}
    # Suite sessions capture the authoritative hardware identity.  Promote a
    # value to the root manifest when every suite agrees, while preserving the
    # suite-level context for mixed or partially captured runs.
    for key in ("gpu", "video_adapter"):
        values = sorted({
            str(summary.get("context", {}).get(key, ""))
            for summary in suite_summaries
            if summary.get("context", {}).get(key) not in (None, "", "unknown")
        })
        if len(values) == 1:
            root_context[key] = values[0]
    deduplicated_review_items: dict[tuple[str, str], dict[str, Any]] = {}
    for item in review_items:
        key = (str(item.get("scenario_id", "")), str(item.get("prompt", "")))
        existing = deduplicated_review_items.get(key)
        # Prefer the suite-qualified copy when a session emitted the same
        # catalog prompt that the merger generated as a fallback.
        if existing is None or (item.get("suite_manifest") and not existing.get("suite_manifest")):
            deduplicated_review_items[key] = item
    return {
        "schema_version": SCHEMA_VERSION,
        "run": root_context,
        "suites": sorted(suite_summaries, key=lambda value: (str(value.get("suite")), str(value.get("variant")))),
        "scenarios": sorted(scenarios, key=lambda value: str(value.get("instance_id", ""))),
        "artifacts": sorted(artifacts, key=lambda value: str(value.get("path", ""))),
        "telemetry": sorted(telemetry, key=lambda value: str(value.get("path", ""))),
        "checks": sorted(checks, key=lambda value: str(value.get("id", ""))),
        "review_items": sorted(deduplicated_review_items.values(), key=lambda value: str(value.get("id", ""))),
        "errors": errors,
        "status": "pass",
    }


def artifact_absolute(bundle: Path, artifact: dict[str, Any]) -> Path:
    path = Path(str(artifact.get("path", "")))
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"artifact path is not relative: {path}")
    resolved_bundle = bundle.resolve()
    resolved = (resolved_bundle / path).resolve()
    try:
        resolved.relative_to(resolved_bundle)
    except ValueError as error:
        raise ValueError(f"artifact path escapes bundle root: {path}") from error
    return resolved


def enrich_artifacts(bundle: Path, manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for artifact in manifest.get("artifacts", []):
        try:
            path = artifact_absolute(bundle, artifact)
        except ValueError as error:
            errors.append(str(error))
            continue
        if not path.is_file():
            artifact["status"] = "missing"
            errors.append(f"artifact is missing: {artifact.get('path', '')}")
            continue
        artifact["bytes"] = path.stat().st_size
        actual_hash = sha256(path)
        declared_hash = artifact.get("sha256")
        if declared_hash and str(declared_hash).lower() != actual_hash:
            errors.append(f"artifact hash is stale: {artifact.get('path', '')}")
        artifact["sha256"] = actual_hash
        extension = path.suffix.lower().lstrip(".")
        artifact["format"] = artifact.get("format") or extension
        if extension == "png":
            try:
                with Image.open(path) as image:
                    declared_width = artifact.get("width")
                    declared_height = artifact.get("height")
                    if declared_width is not None and declared_height is not None and (int(declared_width), int(declared_height)) != image.size:
                        errors.append(f"artifact dimensions disagree: {artifact.get('path', '')}")
                    artifact["width"], artifact["height"] = image.size
            except Exception as error:  # pragma: no cover - Pillow's decoder errors vary by version
                artifact["status"] = "missing"
                errors.append(f"could not decode image {artifact.get('path', '')}: {error}")
        elif extension == "json":
            try:
                with path.open("r", encoding="utf-8") as handle:
                    json.load(handle)
            except (OSError, ValueError, json.JSONDecodeError) as error:
                artifact["status"] = "missing"
                errors.append(f"JSON artifact cannot be decoded: {artifact.get('path', '')}: {error}")
        artifact.setdefault("status", "pass")
    return errors


def compatibility_context(context: dict[str, Any]) -> dict[str, Any]:
    return {key: context.get(key) for key in COMPATIBILITY_KEYS if key in context}


def compatible(actual: dict[str, Any], baseline: dict[str, Any]) -> tuple[bool, list[str]]:
    actual_values = compatibility_context(actual)
    baseline_values = compatibility_context(baseline.get("compatibility", baseline))
    mismatches = []
    for key, expected in baseline_values.items():
        if expected is not None and actual_values.get(key) != expected:
            mismatches.append(f"{key}: actual={actual_values.get(key)!r} baseline={expected!r}")
    return not mismatches, mismatches


def compare_images(candidate: Path, baseline: Path, diff_root: Path, stem: str, thresholds: dict[str, Any]) -> dict[str, Any]:
    with Image.open(candidate).convert("RGBA") as candidate_image, Image.open(baseline).convert("RGBA") as baseline_image:
        if candidate_image.size != baseline_image.size:
            return {"status": "not_comparable", "message": f"image dimensions differ: {candidate_image.size} vs {baseline_image.size}"}
        difference = ImageChops.difference(candidate_image, baseline_image)
        rgb_difference = difference.convert("RGB")
        channel_mean = ImageStat.Stat(rgb_difference).mean
        mean_abs_delta = sum(channel_mean) / (3.0 * 255.0)
        tolerance = int(thresholds.get("pixel_tolerance", DEFAULT_THRESHOLDS["pixel_tolerance"]))
        changed = 0
        sampled = 0
        values: list[int] = []
        pixels = difference.get_flattened_data() if hasattr(difference, "get_flattened_data") else difference.getdata()
        for red, green, blue, _alpha in pixels:
            maximum = max(red, green, blue)
            values.append(maximum)
            sampled += 1
            if maximum > tolerance:
                changed += 1
        values.sort()
        p95 = values[min(len(values) - 1, math.floor(len(values) * 0.95))] / 255.0 if values else 0.0
        changed_fraction = changed / sampled if sampled else 0.0
        diff_root.mkdir(parents=True, exist_ok=True)
        heatmap = ImageOps.colorize(
            difference.convert("L").point(lambda value: min(255, value * 8)),
            black=(5, 16, 30),
            white=(255, 74, 30),
        )
        heatmap_path = diff_root / f"{stem}.heatmap.png"
        overlay_path = diff_root / f"{stem}.overlay.png"
        heatmap.save(heatmap_path)
        Image.blend(baseline_image, candidate_image, 0.5).save(overlay_path)
        over_threshold = mean_abs_delta > float(thresholds.get("mean_abs_delta", DEFAULT_THRESHOLDS["mean_abs_delta"])) or changed_fraction > float(thresholds.get("changed_fraction", DEFAULT_THRESHOLDS["changed_fraction"]))
        return {
            "status": "review_required" if over_threshold else "pass",
            "mean_abs_delta": mean_abs_delta,
            "p95_abs_delta": p95,
            "changed_fraction": changed_fraction,
            "thresholds": thresholds,
            "heatmap_path": heatmap_path,
            "overlay_path": overlay_path,
        }


def baseline_paths(repo_root: Path, suite: str, baseline_id: str) -> tuple[Path, Path]:
    stem = safe_name(baseline_id)
    directory = repo_root / "tests" / "visual_baselines" / safe_name(suite)
    return directory / f"{stem}.png", directory / f"{stem}.json"


def validate_baseline_metadata(repo_root: Path, manifest: dict[str, Any], require_present: bool = False) -> list[str]:
    errors: list[str] = []
    checked: set[tuple[str, str]] = set()
    for scenario in manifest.get("scenarios", []):
        baseline_id = scenario.get("baseline_id")
        if not baseline_id:
            continue
        suite = str(scenario.get("suite", "unknown"))
        key = (suite, str(baseline_id))
        if key in checked:
            continue
        checked.add(key)
        image_path, metadata_path = baseline_paths(repo_root, suite, str(baseline_id))
        if not image_path.exists() and not metadata_path.exists():
            if require_present:
                errors.append(f"declared baseline is missing: {suite}/{baseline_id}")
            continue
        if image_path.exists() != metadata_path.exists():
            errors.append(f"baseline pair is incomplete: {suite}/{baseline_id}")
            continue
        try:
            metadata = read_json(metadata_path)
        except (OSError, ValueError, json.JSONDecodeError) as error:
            errors.append(f"baseline metadata is corrupt: {metadata_path}: {error}")
            continue
        if metadata.get("schema_version") != SCHEMA_VERSION:
            errors.append(f"baseline metadata schema is invalid: {metadata_path}")
        if str(metadata.get("baseline_id", "")) != str(baseline_id):
            errors.append(f"baseline metadata id does not match {baseline_id}: {metadata_path}")
        if str(metadata.get("suite", "")) != suite:
            errors.append(f"baseline metadata suite does not match {suite}: {metadata_path}")
        compatibility = metadata.get("compatibility")
        if not isinstance(compatibility, dict):
            errors.append(f"baseline metadata compatibility is missing: {metadata_path}")
        else:
            for key in COMPATIBILITY_KEYS:
                if key not in compatibility or compatibility.get(key) is None or (isinstance(compatibility.get(key), str) and not compatibility.get(key).strip()):
                    errors.append(f"baseline metadata compatibility is missing {key}: {metadata_path}")
        try:
            with Image.open(image_path) as image:
                expected_width = compatibility.get("capture_width") if isinstance(compatibility, dict) else None
                expected_height = compatibility.get("capture_height") if isinstance(compatibility, dict) else None
                if expected_width is not None and expected_height is not None and image.size != (int(expected_width), int(expected_height)):
                    errors.append(f"baseline dimensions do not match metadata: {image_path}")
        except Exception as error:  # pragma: no cover - Pillow decoder errors vary by version
            errors.append(f"baseline image cannot be decoded: {image_path}: {error}")
    return errors


def choose_baseline_candidate(bundle: Path, artifacts: list[dict[str, Any]], scenario: dict[str, Any]) -> dict[str, Any] | None:
    stable_id = str(scenario.get("stable_id", scenario.get("id", "")))
    candidates = [
        artifact for artifact in artifacts
        if artifact.get("role") == "raw"
        and str(artifact.get("scenario_id", "")) == stable_id
        and artifact.get("format") == "png"
    ]
    if not candidates:
        return None
    candidates.sort(key=lambda artifact: (0 if "canonical_60" in str(artifact.get("path")) else 1, str(artifact.get("path"))))
    return candidates[0]


def update_baselines(repo_root: Path, bundle: Path, manifest: dict[str, Any], allow_dirty: bool) -> list[str]:
    run = manifest.get("run", {})
    git = run.get("git", {}) if isinstance(run.get("git"), dict) else {}
    if bool(git.get("working_tree_dirty", run.get("working_tree_dirty", False))) and not allow_dirty:
        raise ValueError("baseline updates require a clean worktree; pass --allow-dirty-baseline explicitly")
    updated: list[str] = []
    for scenario in manifest.get("scenarios", []):
        baseline_id = scenario.get("baseline_id")
        if not baseline_id:
            continue
        candidate = choose_baseline_candidate(bundle, manifest.get("artifacts", []), scenario)
        if not candidate:
            continue
        candidate_path = artifact_absolute(bundle, candidate)
        destination, metadata_path = baseline_paths(repo_root, str(scenario.get("suite", "unknown")), str(baseline_id))
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(candidate_path, destination)
        write_json(metadata_path, {
            "schema_version": SCHEMA_VERSION,
            "baseline_id": baseline_id,
            "suite": scenario.get("suite"),
            "source_scenario_id": scenario.get("stable_id"),
            "compatibility": compatibility_context(candidate.get("context", {})),
            "thresholds": DEFAULT_THRESHOLDS,
            "source_run_id": run.get("run_id"),
            "source_sha256": sha256(candidate_path),
        })
        updated.append(relative_posix(destination, repo_root))
    return updated


def add_generated_artifact(manifest: dict[str, Any], path: Path, bundle: Path, role: str, scenario_id: str) -> dict[str, Any]:
    artifact = {
        "id": f"{scenario_id}:{role}",
        "scenario_id": scenario_id,
        "scenario_instance_id": scenario_id,
        "role": role,
        "path": relative_posix(path, bundle),
        "format": path.suffix.lower().lstrip("."),
    }
    manifest.setdefault("artifacts", []).append(artifact)
    return artifact


def build_timeline_summaries(bundle: Path, manifest: dict[str, Any]) -> Path:
    summaries: dict[str, Any] = {}
    for telemetry in manifest.get("telemetry", []):
        path = bundle / str(telemetry.get("path", ""))
        if not path.is_file():
            continue
        try:
            payload = read_json(path)
        except (OSError, ValueError, json.JSONDecodeError):
            continue
        rows = payload.get("samples", [])
        if not isinstance(rows, list):
            continue
        numeric: dict[str, list[float]] = {}
        states: Counter[str] = Counter()
        phases: Counter[str] = Counter()
        transitions: list[dict[str, Any]] = []
        previous: tuple[Any, Any] | None = None
        for row in rows:
            if not isinstance(row, dict):
                continue
            state = row.get("state")
            phase = row.get("phase")
            if state is not None:
                states[str(state)] += 1
            if phase is not None:
                phases[str(phase)] += 1
            current = (state, phase)
            if previous is not None and current != previous:
                transitions.append({"from": list(previous), "to": list(current), "time_s": row.get("time_s")})
            previous = current
            for key, value in row.items():
                if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value)):
                    numeric.setdefault(str(key), []).append(float(value))
        summaries[str(telemetry.get("scenario_instance_id", telemetry.get("scenario_id", path.stem)))] = {
            "sample_count": len(rows),
            "first_time_s": rows[0].get("time_s") if rows and isinstance(rows[0], dict) else None,
            "last_time_s": rows[-1].get("time_s") if rows and isinstance(rows[-1], dict) else None,
            "states": dict(states),
            "phases": dict(phases),
            "transitions": transitions,
            "numeric_ranges": {
                key: {"minimum": min(values), "maximum": max(values)}
                for key, values in sorted(numeric.items())
                if values
            },
        }
    path = bundle / "telemetry" / "timeline_summary.json"
    write_json(path, {"schema_version": SCHEMA_VERSION, "scenarios": summaries})
    add_generated_artifact(manifest, path, bundle, "timeline_summary", "visual.timeline")
    return path


def build_contact_sheets(bundle: Path, manifest: dict[str, Any]) -> None:
    grouped: dict[str, list[dict[str, Any]]] = {}
    scenario_by_id = {str(scenario.get("instance_id")): scenario for scenario in manifest.get("scenarios", [])}
    analysis_by_scenario = {
        str(artifact.get("scenario_instance_id")): artifact
        for artifact in manifest.get("artifacts", [])
        if artifact.get("role") == "analysis" and artifact.get("format") == "png"
    }
    for artifact in manifest.get("artifacts", []):
        role = str(artifact.get("role", ""))
        is_motion_frame = role.startswith("motion_frame_")
        is_recovery_phase = role.startswith("raw_")
        if (artifact.get("role") != "raw" and not is_motion_frame and not is_recovery_phase) or artifact.get("format") != "png":
            continue
        # Contact sheets are the first Codex review surface. Prefer the clean
        # analysis frame when an adapter supplied one, while retaining the raw
        # user-visible capture as a separate artifact in the report.
        display_artifact = artifact if is_motion_frame or is_recovery_phase else analysis_by_scenario.get(str(artifact.get("scenario_instance_id")), artifact)
        suite_manifest = str(artifact.get("suite_manifest", ""))
        suite = suite_manifest.split("/")[1] if suite_manifest.startswith("suites/") and len(suite_manifest.split("/")) > 1 else "all"
        if suite == "all":
            suite = str(artifact.get("scenario_id", "all")).split(".")[0]
        if is_motion_frame:
            suite = "motion_%s_%s" % (safe_name(str(artifact.get("scenario_id", "unknown"))), safe_name(str(artifact.get("variant", "unknown"))))
        elif is_recovery_phase:
            suite = "recovery_%s_%s" % (safe_name(str(artifact.get("scenario_id", "unknown"))), safe_name(str(artifact.get("variant", "unknown"))))
        scenario = scenario_by_id.get(str(artifact.get("scenario_instance_id")), {})
        state = str(scenario.get("state", artifact.get("context", {}).get("state", "unknown")))
        view = str(scenario.get("view", artifact.get("context", {}).get("view", "unknown")))
        grouped.setdefault(safe_name(f"{suite}_{state}_{view}"), []).append(display_artifact)
    font = ImageFont.load_default()
    for suite, artifacts in sorted(grouped.items()):
        artifacts.sort(key=lambda value: str(value.get("path", "")))
        tile_width, tile_height, label_height = 320, 180, 34
        columns = 4
        rows = max(1, math.ceil(len(artifacts) / columns))
        sheet = Image.new("RGB", (columns * tile_width, rows * (tile_height + label_height)), (20, 28, 38))
        draw = ImageDraw.Draw(sheet)
        for index, artifact in enumerate(artifacts):
            path = bundle / str(artifact["path"])
            try:
                with Image.open(path).convert("RGB") as source:
                    thumbnail = ImageOps.contain(source, (tile_width - 8, tile_height - 8))
                    x = (index % columns) * tile_width + (tile_width - thumbnail.width) // 2
                    y = (index // columns) * (tile_height + label_height) + (tile_height - thumbnail.height) // 2
                    sheet.paste(thumbnail, (x, y))
            except Exception:
                continue
            scenario = scenario_by_id.get(str(artifact.get("scenario_instance_id")), {})
            label = f"{artifact.get('scenario_id', 'unknown')}\n{scenario.get('phase', artifact.get('context', {}).get('phase', ''))} / {artifact.get('variant', '')}"
            draw.text(((index % columns) * tile_width + 4, (index // columns) * (tile_height + label_height) + tile_height + 2), label[:90], fill=(235, 242, 248), font=font)
        output = bundle / "contact_sheets" / f"{safe_name(suite)}.png"
        output.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(output)
        add_generated_artifact(manifest, output, bundle, "contact_sheet", f"visual.contact_sheet.{suite}")


def _normalized_roi_box(roi: Any, image_size: tuple[int, int]) -> tuple[int, int, int, int] | None:
    if not isinstance(roi, dict):
        return None
    try:
        x = float(roi.get("x", 0.0))
        y = float(roi.get("y", 0.0))
        width = float(roi.get("width", 1.0))
        height = float(roi.get("height", 1.0))
    except (TypeError, ValueError):
        return None
    if not all(math.isfinite(value) for value in [x, y, width, height]) or width <= 0.0 or height <= 0.0:
        return None
    image_width, image_height = image_size
    left = max(0, min(image_width - 1, round(x * image_width)))
    top = max(0, min(image_height - 1, round(y * image_height)))
    right = max(left + 1, min(image_width, round((x + width) * image_width)))
    bottom = max(top + 1, min(image_height, round((y + height) * image_height)))
    return left, top, right, bottom


def build_subject_crops(bundle: Path, manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    scenario_by_id = {str(scenario.get("instance_id")): scenario for scenario in manifest.get("scenarios", [])}
    analysis_by_scenario = {
        str(artifact.get("scenario_instance_id")): artifact
        for artifact in manifest.get("artifacts", [])
        if artifact.get("role") == "analysis" and artifact.get("format") == "png"
    }
    for artifact in list(manifest.get("artifacts", [])):
        if artifact.get("role") != "raw" or artifact.get("format") != "png":
            continue
        scenario = scenario_by_id.get(str(artifact.get("scenario_instance_id")))
        if not scenario:
            continue
        source_artifact = analysis_by_scenario.get(str(artifact.get("scenario_instance_id")), artifact)
        try:
            source_path = artifact_absolute(bundle, source_artifact)
        except ValueError as error:
            errors.append(str(error))
            continue
        try:
            with Image.open(source_path) as source:
                image = source.convert("RGB")
                box = _normalized_roi_box(scenario.get("roi"), image.size)
                if box is None:
                    errors.append(f"scenario ROI is invalid: {scenario.get('instance_id', scenario.get('id', 'unknown'))}")
                    image.close()
                    continue
                crop = image.crop(box)
                image.close()
        except Exception as error:  # pragma: no cover - Pillow decoder errors vary by version
            errors.append(f"subject crop could not read {artifact.get('path', '')}: {error}")
            continue
        suite = safe_name(str(scenario.get("suite", "unknown")))
        instance_id = safe_name(str(scenario.get("instance_id", scenario.get("id", "unknown"))))
        output = bundle / "artifacts" / "crops" / suite / f"{instance_id}.png"
        output.parent.mkdir(parents=True, exist_ok=True)
        crop.save(output)
        generated = add_generated_artifact(manifest, output, bundle, "subject_crop", str(scenario.get("instance_id", scenario.get("id", "unknown"))))
        generated["roi"] = scenario.get("roi")
    return errors


def compare_baselines(repo_root: Path, bundle: Path, manifest: dict[str, Any]) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    scenario_by_id = {str(scenario.get("instance_id")): scenario for scenario in manifest.get("scenarios", [])}
    for artifact in list(manifest.get("artifacts", [])):
        if artifact.get("role") != "raw" or artifact.get("format") != "png":
            continue
        scenario = scenario_by_id.get(str(artifact.get("scenario_instance_id")))
        if not scenario or not scenario.get("baseline_id"):
            continue
        baseline, metadata_path = baseline_paths(repo_root, str(scenario.get("suite", "unknown")), str(scenario["baseline_id"]))
        comparison: dict[str, Any] = {
            "scenario_id": artifact.get("scenario_instance_id"),
            "baseline_id": scenario.get("baseline_id"),
            "candidate_path": artifact.get("path"),
            "baseline_path": relative_posix(baseline, repo_root) if baseline.exists() else None,
        }
        if not baseline.exists():
            comparison.update({"status": "not_comparable", "message": "curated baseline is not present"})
            artifact["comparison"] = comparison
            results.append(comparison)
            continue
        try:
            baseline_metadata = read_json(metadata_path) if metadata_path.is_file() else {}
        except (OSError, ValueError, json.JSONDecodeError) as error:
            comparison.update({"status": "not_comparable", "message": f"baseline metadata is unreadable: {error}"})
            artifact["comparison"] = comparison
            results.append(comparison)
            continue
        is_compatible, mismatches = compatible(artifact.get("context", {}), baseline_metadata)
        if not is_compatible:
            comparison.update({"status": "not_comparable", "message": "reference context differs", "mismatches": mismatches})
            artifact["comparison"] = comparison
            results.append(comparison)
            continue
        thresholds = baseline_metadata.get("thresholds", DEFAULT_THRESHOLDS)
        candidate_path = artifact_absolute(bundle, artifact)
        diff = compare_images(candidate_path, baseline, bundle / "diffs", safe_name(str(artifact.get("scenario_instance_id"))), thresholds)
        for key, value in diff.items():
            if key.endswith("_path") and isinstance(value, Path):
                diff[key] = relative_posix(value, bundle)
                role = "diff_heatmap" if key == "heatmap_path" else "diff_overlay"
                add_generated_artifact(manifest, value, bundle, role, str(artifact.get("scenario_instance_id")))
        comparison.update(diff)
        artifact["comparison"] = comparison
        results.append(comparison)
    return results


def determine_status(manifest: dict[str, Any], comparisons: list[dict[str, Any]], structural_errors: list[str]) -> str:
    if structural_errors or manifest.get("errors"):
        return "missing" if any("missing" in error or "artifact" in error for error in structural_errors) else "fail"
    if any(str(check.get("status")) in {"fail", "missing"} for check in manifest.get("checks", [])):
        return "fail"
    if any(str(summary.get("status")) != "pass" or int(summary.get("exit_code", 0)) != 0 for summary in manifest.get("suites", [])):
        return "fail"
    if any(result.get("status") == "review_required" for result in comparisons):
        return "review_required"
    if any(result.get("status") == "not_comparable" for result in comparisons):
        return "not_comparable"
    return "pass"


def write_report(bundle: Path, manifest: dict[str, Any], comparisons: list[dict[str, Any]], baseline_updates: list[str]) -> Path:
    status = str(manifest.get("status", "missing"))
    scenarios = manifest.get("scenarios", [])
    checks = manifest.get("checks", [])
    lines = [
        "# Codex visual evidence report",
        "",
        f"**Status:** `{status}`  ",
        f"**Run:** `{manifest.get('run', {}).get('run_id', 'unknown')}`  ",
        f"**Manifest:** [visual_run.json](visual_run.json)",
        "",
        "This report separates blocking semantic/evidence failures from advisory rendered-image review. Open the suite/state/view contact sheets first, then the listed subject crops and heatmaps or overlays.",
        "",
        "## Review entry points",
        "",
    ]
    for artifact in manifest.get("artifacts", []):
        if artifact.get("role") == "contact_sheet":
            lines.append(f"- [{artifact.get('scenario_id')}]({artifact.get('path')})")
    lines.extend([
        "",
        "## Recommended review order",
        "",
        "1. Contact sheets, grouped by suite, state, and view.",
        "2. Failed or missing semantic/evidence checks below.",
        "3. Subject crops for skier, snow, landing, and feature readability.",
        "4. Baseline heatmaps and overlays for entries marked `review_required`.",
    ])
    lines.extend(["", "## Scenario results", "", "| Scenario | State/phase | Comparison | Evidence |", "|---|---|---|---|"])
    comparison_by_id = {str(result.get("scenario_id")): result for result in comparisons}
    for scenario in scenarios:
        instance_id = str(scenario.get("instance_id", scenario.get("id", "unknown")))
        comparison = comparison_by_id.get(instance_id, {})
        evidence = [
            f"[{artifact.get('role')}]({artifact.get('path')})"
            for artifact in manifest.get("artifacts", [])
            if str(artifact.get("scenario_instance_id")) == instance_id and artifact.get("role") in {"raw", "analysis", "subject_crop", "timeline", "telemetry", "profile", "diff_heatmap", "diff_overlay"}
        ]
        phase = f"{scenario.get('state', '')} / {scenario.get('phase', '')}"
        comparison_text = str(comparison.get("status", "semantic-only"))
        if comparison.get("status") == "review_required":
            comparison_text += f" (delta {float(comparison.get('mean_abs_delta', 0.0)):.3f}, changed {float(comparison.get('changed_fraction', 0.0)):.1%})"
        lines.append(f"| `{instance_id}` | {phase} | {comparison_text} | {' · '.join(evidence) or 'missing'} |")
    lines.extend(["", "## Checks", "", "| Check | Kind | Status | Message |", "|---|---|---|---|"])
    for check in checks:
        message = str(check.get("message", "")).replace("|", "\\|")
        lines.append(f"| `{check.get('id', '')}` | {check.get('kind', '')} | `{check.get('status', '')}` | {message} |")
    review_items = manifest.get("review_items", [])
    if review_items:
        lines.extend(["", "## Human/Codex review prompts", ""])
        for item in review_items:
            lines.append(f"- `{item.get('scenario_id', '')}` — {item.get('prompt', '')}")
    errors = manifest.get("errors", [])
    if errors:
        lines.extend(["", "## Missing or malformed evidence", ""])
        lines.extend(f"- {error}" for error in errors)
    timeline_path = next((artifact.get("path") for artifact in manifest.get("artifacts", []) if artifact.get("role") == "timeline_summary"), None)
    if timeline_path:
        lines.extend(["", f"Timeline summary: [{timeline_path}]({timeline_path})"])
    if baseline_updates:
        lines.extend(["", "## Baselines updated", ""])
        lines.extend(f"- `{path}`" for path in baseline_updates)
    report = bundle / "visual_report.md"
    report.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return report


def validate_manifest(bundle: Path, manifest: dict[str, Any], catalog: dict[str, Any] | None = None) -> list[str]:
    errors: list[str] = []
    telemetry_payloads: dict[str, dict[str, Any]] = {}
    required = ["schema_version", "run", "suites", "scenarios", "artifacts", "checks", "review_items", "status"]
    errors.extend(f"root manifest missing {key}" for key in required if key not in manifest)
    if manifest.get("schema_version") != SCHEMA_VERSION:
        errors.append(f"schema_version must equal {SCHEMA_VERSION}")
    if manifest.get("status") not in VALID_STATUSES:
        errors.append(f"invalid root manifest status: {manifest.get('status')}")
    for collection_name in ["suites", "scenarios", "artifacts", "checks", "review_items"]:
        if collection_name in manifest and not isinstance(manifest[collection_name], list):
            errors.append(f"manifest {collection_name} must be an array")
    instance_ids = [str(scenario.get("instance_id", "")) for scenario in manifest.get("scenarios", [])]
    duplicates = [identifier for identifier, count in Counter(instance_ids).items() if identifier and count > 1]
    errors.extend(f"duplicate scenario instance: {identifier}" for identifier in duplicates)
    artifact_ids = [str(artifact.get("id", "")) for artifact in manifest.get("artifacts", [])]
    duplicate_artifacts = [identifier for identifier, count in Counter(artifact_ids).items() if identifier and count > 1]
    errors.extend(f"duplicate artifact id: {identifier}" for identifier in duplicate_artifacts)
    expected_scenarios = manifest.get("run", {}).get("expected_scenarios", []) if isinstance(manifest.get("run"), dict) else []
    present_stable_ids = {str(scenario.get("stable_id", scenario.get("id", ""))) for scenario in manifest.get("scenarios", [])}
    if isinstance(expected_scenarios, list):
        errors.extend(f"expected scenario is missing: {identifier}" for identifier in expected_scenarios if str(identifier) not in present_stable_ids)
    for artifact in manifest.get("artifacts", []):
        try:
            path = artifact_absolute(bundle, artifact)
        except ValueError as error:
            errors.append(str(error))
            continue
        if not path.is_file():
            errors.append(f"artifact is missing: {artifact.get('path', '')}")
            continue
        declared_hash = artifact.get("sha256")
        if declared_hash and str(declared_hash).lower() != sha256(path):
            errors.append(f"manifest artifact hash is stale: {artifact.get('path', '')}")
        if artifact.get("format") == "png" and path.is_file():
            try:
                with Image.open(path) as image:
                    if artifact.get("width") and artifact.get("height") and (artifact["width"], artifact["height"]) != image.size:
                        errors.append(f"manifest image dimensions are stale: {artifact.get('path', '')}")
            except Exception as error:
                errors.append(f"image cannot be decoded: {artifact.get('path', '')}: {error}")
        elif artifact.get("format") == "json":
            try:
                with path.open("r", encoding="utf-8") as handle:
                    json.load(handle)
            except (OSError, ValueError, json.JSONDecodeError) as error:
                errors.append(f"JSON artifact cannot be decoded: {artifact.get('path', '')}: {error}")
    for telemetry in manifest.get("telemetry", []):
        try:
            path = artifact_absolute(bundle, telemetry)
        except ValueError as error:
            errors.append(str(error))
            continue
        if not path.is_file():
            errors.append(f"telemetry is missing: {telemetry.get('path', '')}")
            continue
        try:
            with path.open("r", encoding="utf-8") as handle:
                payload = json.load(handle)
            if not isinstance(payload, dict):
                errors.append(f"telemetry must be a JSON object: {telemetry.get('path', '')}")
            else:
                telemetry_payloads[str(telemetry.get("scenario_instance_id", telemetry.get("scenario_id", "")))] = payload
        except (OSError, ValueError, json.JSONDecodeError) as error:
            errors.append(f"telemetry cannot be decoded: {telemetry.get('path', '')}: {error}")
    for check in manifest.get("checks", []):
        if check.get("status") not in VALID_STATUSES:
            errors.append(f"invalid check status: {check.get('status')}")
    for scenario in manifest.get("scenarios", []):
        instance_id = str(scenario.get("instance_id", scenario.get("id", "")))
        definition = catalog_entry(catalog, str(scenario.get("stable_id", scenario.get("id", "")))) if catalog is not None else scenario
        required_roles = definition.get("required_artifacts", []) if isinstance(definition, dict) else []
        available_roles = {
            str(artifact.get("role"))
            for artifact in manifest.get("artifacts", [])
            if str(artifact.get("scenario_instance_id")) == instance_id
        }
        for role in required_roles:
            if str(role) not in available_roles:
                errors.append(f"scenario {instance_id} is missing required artifact role: {role}")
        semantic_checks = {str(check) for check in definition.get("semantic_checks", [])} if isinstance(definition, dict) else set()
        telemetry_payload = telemetry_payloads.get(instance_id, {})
        samples = telemetry_payload.get("samples", []) if isinstance(telemetry_payload, dict) else []
        if "finite_telemetry" in semantic_checks:
            def finite_value(value: Any) -> bool:
                if isinstance(value, float):
                    return math.isfinite(value)
                if isinstance(value, dict):
                    return all(finite_value(child) for child in value.values())
                if isinstance(value, list):
                    return all(finite_value(child) for child in value)
                return True
            if not isinstance(samples, list) or not finite_value(samples):
                errors.append(f"scenario {instance_id} contains non-finite telemetry")
        if "monotonic_time" in semantic_checks:
            times = [float(row["time_s"]) for row in samples if isinstance(row, dict) and isinstance(row.get("time_s"), (int, float))]
            if len(times) != len(samples) or any(later < earlier for earlier, later in zip(times, times[1:])):
                errors.append(f"scenario {instance_id} telemetry time is not monotonic")
        recovery_phases = {str(row.get("phase")) for row in samples if isinstance(row, dict)} if isinstance(samples, list) else set()
        for required_phase, check_name in [("started", "recovery_started"), ("respawned", "recovery_respawned"), ("completed", "recovery_completed")]:
            if check_name in semantic_checks and required_phase not in recovery_phases:
                errors.append(f"scenario {instance_id} is missing recovery phase: {required_phase}")
    def walk(value: Any, key: str = "") -> None:
        if isinstance(value, dict):
            for child_key, child_value in value.items():
                walk(child_value, str(child_key))
        elif isinstance(value, list):
            for child in value:
                walk(child, key)
        elif isinstance(value, str) and (key.endswith("_m") or key.endswith("_rad")) and value.startswith("("):
            errors.append(f"telemetry field {key} is stringified instead of structured")
    walk(manifest)
    return errors


def build(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).resolve()
    bundle = Path(args.bundle).resolve()
    catalog = load_catalog(repo_root)
    manifests = discover_suite_manifests(bundle)
    manifest = merge_suite_manifests(bundle, manifests, catalog)
    structural_errors = validate_catalog(catalog)
    if not manifests:
        structural_errors.append("no suite manifests were discovered under suites/")
    structural_errors.extend(enrich_artifacts(bundle, manifest))
    baseline_updates: list[str] = []
    if args.update_baselines:
        baseline_updates = update_baselines(repo_root, bundle, manifest, args.allow_dirty_baseline)
    build_timeline_summaries(bundle, manifest)
    build_contact_sheets(bundle, manifest)
    structural_errors.extend(build_subject_crops(bundle, manifest))
    comparisons = compare_baselines(repo_root, bundle, manifest)
    manifest["comparisons"] = comparisons
    manifest["generated_at_utc"] = datetime.now(timezone.utc).isoformat()
    structural_errors.extend(validate_baseline_metadata(repo_root, manifest, require_present=True))
    structural_errors.extend(enrich_artifacts(bundle, manifest))
    manifest["status"] = determine_status(manifest, comparisons, structural_errors)
    manifest["errors"] = sorted(set([*manifest.get("errors", []), *structural_errors]))
    manifest["run"].setdefault("bundle_root", str(bundle))
    manifest_path = bundle / "visual_run.json"
    write_json(manifest_path, as_json_value(manifest))
    report = write_report(bundle, manifest, comparisons, baseline_updates)
    validation_errors = validate_manifest(bundle, manifest, catalog)
    if validation_errors:
        manifest["status"] = "missing"
        manifest["errors"] = sorted(set([*manifest.get("errors", []), *validation_errors]))
        write_json(manifest_path, as_json_value(manifest))
        write_report(bundle, manifest, comparisons, baseline_updates)
        for error in validation_errors:
            print(f"VISUAL_EVIDENCE_SCHEMA_FAIL: {error}")
        return 1
    print(f"CODEX_VISUAL_MANIFEST: {manifest_path}")
    print(f"CODEX_VISUAL_REPORT: {report}")
    print(f"CODEX_VISUAL_STATUS: {manifest['status']}")
    return 1 if manifest["status"] in {"fail", "missing"} else 0


def validate(args: argparse.Namespace) -> int:
    bundle = Path(args.bundle).resolve()
    manifest_path = bundle / "visual_run.json"
    if not manifest_path.is_file():
        print(f"VISUAL_EVIDENCE_SCHEMA_FAIL: manifest is missing: {manifest_path}")
        return 1
    try:
        manifest = read_json(manifest_path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"VISUAL_EVIDENCE_SCHEMA_FAIL: {error}")
        return 1
    catalog = load_catalog(Path(args.repo_root).resolve()) if args.repo_root else None
    errors = validate_catalog(catalog) if catalog is not None else []
    errors.extend(validate_manifest(bundle, manifest, catalog))
    if args.repo_root:
        errors.extend(validate_baseline_metadata(Path(args.repo_root).resolve(), manifest, require_present=True))
    if errors:
        for error in errors:
            print(f"VISUAL_EVIDENCE_SCHEMA_FAIL: {error}")
        return 1
    print(f"VISUAL_EVIDENCE_SCHEMA_PASS: {manifest_path}")
    return 0


def acceptance(args: argparse.Namespace) -> int:
    """Exercise the validator's malformed/missing evidence fixtures in isolation."""
    with tempfile.TemporaryDirectory(prefix="visual-evidence-acceptance-") as temporary:
        root = Path(temporary)
        image_path = root / "artifacts" / "sample.png"
        image_path.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGBA", (4, 4), (90, 140, 180, 255)).save(image_path)
        valid_manifest: dict[str, Any] = {
            "schema_version": SCHEMA_VERSION,
            "run": {"expected_scenarios": ["fixture.sample"]},
            "suites": [{"suite": "fixture", "status": "pass", "exit_code": 0}],
            "scenarios": [{
                "id": "fixture.sample",
                "stable_id": "fixture.sample",
                "instance_id": "fixture.sample",
                "suite": "fixture",
                "suite_manifest": "suites/fixture/canonical/visual_run.json",
                "required_artifacts": ["raw"],
            }],
            "artifacts": [{
                "id": "fixture.sample:raw",
                "scenario_instance_id": "fixture.sample",
                "role": "raw",
                "path": "artifacts/sample.png",
                "format": "png",
                "width": 4,
                "height": 4,
                "sha256": sha256(image_path),
            }],
            "telemetry": [],
            "checks": [],
            "review_items": [],
            "status": "pass",
        }
        valid_errors = validate_manifest(root, valid_manifest)
        if valid_errors:
            print(f"VISUAL_EVIDENCE_ACCEPTANCE_FIXTURES_FAIL: valid fixture rejected: {valid_errors}")
            return 1
        changed_baseline = root / "baseline.png"
        Image.new("RGBA", (4, 4), (220, 60, 40, 255)).save(changed_baseline)
        comparison = compare_images(image_path, changed_baseline, root / "diffs", "fixture", DEFAULT_THRESHOLDS)
        if comparison.get("status") != "review_required" or not Path(comparison["heatmap_path"]).is_file() or not Path(comparison["overlay_path"]).is_file():
            print(f"VISUAL_EVIDENCE_ACCEPTANCE_FIXTURES_FAIL: changed baseline did not produce advisory diff artifacts: {comparison}")
            return 1
        comparable, mismatches = compatible({"godot_version": "4.7.2", "renderer": "Forward+", "gpu": "reference"}, {"compatibility": {"godot_version": "4.7.2", "renderer": "gl_compatibility", "gpu": "reference"}})
        if comparable or not mismatches:
            print("VISUAL_EVIDENCE_ACCEPTANCE_FIXTURES_FAIL: renderer mismatch was treated as comparable")
            return 1

        cases: list[tuple[str, dict[str, Any], str]] = []
        missing_image = deepcopy(valid_manifest)
        missing_image["artifacts"][0]["path"] = "artifacts/missing.png"
        cases.append(("missing images", missing_image, "artifact is missing"))
        wrong_dimensions = deepcopy(valid_manifest)
        wrong_dimensions["artifacts"][0]["width"] = 8
        cases.append(("wrong dimensions", wrong_dimensions, "manifest image dimensions are stale"))
        duplicate_scenarios = deepcopy(valid_manifest)
        duplicate_scenarios["scenarios"].append(deepcopy(duplicate_scenarios["scenarios"][0]))
        cases.append(("duplicate scenario IDs", duplicate_scenarios, "duplicate scenario instance"))
        stale_hash = deepcopy(valid_manifest)
        stale_hash["artifacts"][0]["sha256"] = "0" * 64
        cases.append(("stale artifacts", stale_hash, "manifest artifact hash is stale"))
        unsafe_path = deepcopy(valid_manifest)
        unsafe_path["artifacts"][0]["path"] = "../escape.png"
        cases.append(("unsafe output paths", unsafe_path, "artifact path is not relative"))
        corrupt_json = deepcopy(valid_manifest)
        corrupt_path = root / "artifacts" / "corrupt.json"
        corrupt_path.write_text("{not-json", encoding="utf-8")
        corrupt_json["artifacts"].append({"id": "fixture.corrupt:metadata", "role": "metadata", "path": "artifacts/corrupt.json", "format": "json"})
        cases.append(("corrupt JSON", corrupt_json, "JSON artifact cannot be decoded"))
        for label, fixture, expected in cases:
            errors = validate_manifest(root, fixture)
            if not any(expected in error for error in errors):
                print(f"VISUAL_EVIDENCE_ACCEPTANCE_FIXTURES_FAIL: {label} did not produce {expected!r}: {errors}")
                return 1

        baseline_repo = root / "repo"
        baseline_image, baseline_metadata = baseline_paths(baseline_repo, "fixture", "fixture.baseline")
        baseline_image.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGBA", (4, 4), (90, 140, 180, 255)).save(baseline_image)
        baseline_metadata.write_text(json.dumps({"schema_version": "wrong", "baseline_id": "other"}), encoding="utf-8")
        baseline_manifest = deepcopy(valid_manifest)
        baseline_manifest["scenarios"][0]["baseline_id"] = "fixture.baseline"
        baseline_errors = validate_baseline_metadata(baseline_repo, baseline_manifest)
        if not baseline_errors:
            print("VISUAL_EVIDENCE_ACCEPTANCE_FIXTURES_FAIL: invalid baseline metadata was accepted")
            return 1
    print("VISUAL_EVIDENCE_ACCEPTANCE_FIXTURES_PASS: missing images, corrupt JSON, dimensions, duplicate IDs, stale hashes, unsafe paths, and baseline metadata")
    return 0


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    build_parser = subparsers.add_parser("build")
    build_parser.add_argument("--repo-root", required=True)
    build_parser.add_argument("--bundle", required=True)
    build_parser.add_argument("--update-baselines", action="store_true")
    build_parser.add_argument("--allow-dirty-baseline", action="store_true")
    build_parser.set_defaults(function=build)
    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--bundle", required=True)
    validate_parser.add_argument("--repo-root", required=False, default="")
    validate_parser.set_defaults(function=validate)
    acceptance_parser = subparsers.add_parser("acceptance")
    acceptance_parser.set_defaults(function=acceptance)
    return parser


if __name__ == "__main__":
    try:
        parsed_args = make_parser().parse_args()
        sys.exit(parsed_args.function(parsed_args))
    except Exception as error:  # pragma: no cover - command-line safety net
        print(f"VISUAL_EVIDENCE_TOOL_FAIL: {error}")
        sys.exit(1)
