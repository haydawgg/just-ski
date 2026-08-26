# Known Issues

- Automated smoke testing covers launch, scene construction, slope contact, and downhill acceleration. Movement feel, camera comfort, rail capture tolerance, and landing thresholds still require controller play-tuning.
- Xbox, PlayStation, and generic mappings use Godot/SDL abstraction, but no physical controllers were available to verify glyph family detection, hot-plug behavior, or rumble strength.
- The current character is a detailed articulated procedural rig rather than a skinned production humanoid. Its hierarchy and small animation interface are intentionally replaceable by a retargeted Skeleton3D adapter later.
- Leg flex, boot/ski attachment, and procedural two-bone hand reach provide terrain- and trick-aware posing, but a production Skeleton3D/AnimationTree rig and PhysicalBoneSimulator3D ragdoll remain future art-pipeline work. Bail currently uses an authored procedural tumble before respawn.
- Graphics settings apply render scale and high-level environment effects. The menu does not yet expose every advanced Godot 4.7 renderer option listed in the long-term plan (FSR2, HDR, GI mode, reflection quality, and risky-resolution confirmation).
- Audio currently uses a lightweight procedural speed/skid/rail layer. Authored powder, ice, wind, impact, ambience, and spatial feature recordings are not yet included.
- The graybox provides multiple connected lines but has not received the final art, vegetation density, resort expansion, LOD, or profiler-driven 1080p High optimization pass.
- Thin-feature collision and grind capture have not yet been stress-tested at maximum speed for a 20-minute session.
