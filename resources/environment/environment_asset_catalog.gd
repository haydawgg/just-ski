class_name EnvironmentAssetCatalog
extends Resource

## Authoritative registry for production environment assets and their scale /
## collision semantics.  The current project has no imported environment pack,
## so entries may intentionally use the procedural graybox until a visual scene
## is assigned.  Production mode can reject those entries explicitly.

enum AssetMode { AUTO, PRODUCTION, GRAYBOX_FALLBACK }

@export var mode: AssetMode = AssetMode.AUTO
@export var definitions: Array[EnvironmentAssetDefinition] = []

func definition_for(asset_id: String) -> EnvironmentAssetDefinition:
	for definition: EnvironmentAssetDefinition in definitions:
		if definition != null and definition.asset_id == asset_id:
			return definition
	return null

func validate(require_production_scenes: bool = false) -> Array[String]:
	var failures: Array[String] = []
	var seen: Dictionary = {}
	for definition: EnvironmentAssetDefinition in definitions:
		if definition == null:
			failures.append("catalog contains a null definition")
			continue
		for reason: String in definition.validate():
			failures.append("%s: %s" % [definition.asset_id, reason])
		if seen.has(definition.asset_id):
			failures.append("duplicate asset_id %s" % definition.asset_id)
		seen[definition.asset_id] = true
		if require_production_scenes and not definition.has_production_scene():
			failures.append("%s: production visual scene is missing" % definition.asset_id)
	return failures

func should_use_production_scenes() -> bool:
	return mode == AssetMode.PRODUCTION

func scene_for(asset_id: String) -> PackedScene:
	var definition := definition_for(asset_id)
	if definition == null or not definition.has_production_scene():
		return null
	return definition.visual_scene

func should_use_scene(asset_id: String) -> bool:
	var definition := definition_for(asset_id)
	if definition == null or not definition.has_production_scene():
		return false
	return mode != AssetMode.GRAYBOX_FALLBACK
