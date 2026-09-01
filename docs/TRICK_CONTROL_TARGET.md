# Trick Control Target

## Design target

The trick system should aim for:

**Steep-like analog freedom + stronger physical takeoff commitment + stricter landing consequences.**

The goal is not to copy Steep's exact controls or reproduce its trick system one-to-one. The goal is to capture the part of that game that makes tricks feel expressive and continuous: the player should feel like they are controlling the skier's rotational state and body position, not selecting canned trick commands.

The target control flow is:

**preload → analog throw vector → persistent angular momentum → tuck/open/check → physical landing**

This should replace the less physical mental model of:

**gesture → named trick family → impulse → repeated airborne commands → landing**

## Core principles

### 1. Rotation is committed at takeoff

Major spin, flip, and cork authority should come from the setup and release before or at the lip.

The quality of the preload should determine how much useful rotation the player takes into the air. Setup depth, hold time, release speed, and release direction should all matter.

A weak preload should stay weak. The player should not be able to leave the ground neutral and manufacture a large trick halfway through the jump.

### 2. Air control is continuous management, not new trick generation

Once airborne, input should manage angular momentum that already exists.

Air control should let the player:

- preserve rotation,
- accelerate an existing rotation modestly through a compact body shape,
- slow or check rotation by opening the body,
- make small orientation corrections,
- intentionally let a trick overrotate,
- prepare for landing.

It should not let the player repeatedly create full-strength rotation impulses.

The feel should be **commitment, then management**.

### 3. Stick input should describe a physical throw

The right-stick release should increasingly behave like an analog throw vector rather than only a classifier for discrete trick names.

Horizontal input should bias toward flatter spin rotation.

Vertical input should bias toward flip rotation.

Diagonal input should create continuously varying off-axis rotation instead of selecting one fixed cork ratio.

The player should be able to discover slightly different axes through slightly different releases while still receiving predictable results.

### 4. Body shape should explain rotation speed

Airborne rotation should respond to gameplay-owned body compactness.

A compact skier should have lower effective rotational inertia and preserve or increase the speed of an existing rotation.

An open skier should have higher effective inertia and slow the rotation.

This should be the primary explanation for the player's ability to speed up or check a trick. Hidden automatic angular damping should be secondary.

Animation should visualize the gameplay state; animation must never drive the gameplay physics backward.

### 5. The player should be able to check or overrotate

A good system should not automatically stop the skier at the correct rotation.

The player should be able to:

- open too early and underrotate,
- stay compact too long and overrotate,
- check a rotation deliberately,
- carry excess angular velocity into the landing,
- land a technically completed trick badly.

This gives the trick system meaningful timing and consequence.

### 6. Rotation should remain analog even when scoring is discrete

Gameplay rotation is continuous.

Scoring may eventually credit discrete values such as 180, 360, 540, or 720, but those values should be derived from the physical result rather than commanded directly.

The game should maintain an authoritative accumulated rotation and signed residual.

Example:

- actual rotation: 326°
- credited candidate: 360°
- residual: -34°

That residual should influence landing quality, scoring, animation, and feedback consistently.

### 7. Grabs should remain highly expressive

The current trigger-as-hand and right-stick-as-grab/style language is a good fit for this target.

Grabs should not simply move a hand to a marker. They should reshape the skier:

- compress the target knee,
- move the ski toward the hand,
- shift the pelvis,
- counterbalance the torso,
- change the free arm silhouette,
- influence compactness and therefore the existing rotation.

A grab should feel like part of the physical trick rather than a cosmetic overlay.

### 8. Assistance should widen the player's margin, not perform the trick

Landing assistance can remain available, but it should not secretly finish missing rotation or automatically brake every trick into alignment.

Assistance may:

- make checking rotation slightly easier,
- widen acceptable landing tolerances,
- help stabilize a nearly aligned landing,
- reduce punishing edge cases.

It should not create rotation, finish an incomplete trick, or hide the true signed rotation residual.

## Relationship to Steep

The useful reference point from Steep is its sense of analog freedom and continuous rotational control.

Summit Sessions should keep its own identity by making takeoff preparation more important and physical than a purely permissive airborne trick system.

The desired distinction is:

**Steep inspiration:** expressive analog rotation, variable axes, continuous rider control, readable grabs, player-managed landing timing.

**Summit Sessions identity:** stronger preload requirement, more ballistic angular momentum, less ability to create rotation from neutral in the air, stricter residual-based landings, and clearer physical consequences for underrotation and overrotation.

The result should feel expressive without feeling motorized.

## Current implementation alignment

The mechanical redesign now implements this target.

Implemented:

- preload depth, duration, and release speed contribute to takeoff quality,
- the minimum effective takeoff strength has been lowered so weak setups remain meaningfully weak,
- one continuous takeoff axis is authored from release direction, ski pressure, and edge input,
- spin, cork, and flip are derived presentation regions rather than separate physical impulse families,
- takeoff rotation is distributed across a short release window instead of arriving as one instantaneous impulse,
- neutral airborne spin/cork/flip flicks are rejected,
- held airborne input continuously manages compactness/inertia without adding repeated impulses,
- precision air trim draws from one finite, non-regenerating assist budget,
- signed rotation residuals and stricter completion thresholds exist,
- a persistent `TrickRotationState` owns the committed axis, reference-frame progress, quaternion orientation delta, release state, compactness, inertia, and assist accounting,
- a quaternion air-rotation integrator exists and has acceptance coverage,
- compactness/inertia behavior has deterministic test coverage,
- `SkierController` now uses quaternion integration and `TrickRotationState` for live reference-frame progress,
- gameplay-owned compactness now changes live rotational inertia and damping while animation reads the same value,
- authoritative signed residuals now feed landing classification, scoring, and animation from one rotation history,
- late-air automatic damping has been reduced to a conservative safety layer behind visible body opening,
- every rotational takeoff varies continuously with release direction while preserving mirrored behavior,
- forward/back ski pressure blends pitch into the same axis while neutral pressure preserves a straight vertical pop,
- trick naming, credited degrees, residuals, HUD data, and animation weights are derived from the physical axis,
- held committed/opposite input projects onto that axis and changes body shape rather than issuing a new trick command,
- trick rotation benchmark and live control regression tests have been added.

## Remaining gaps

The code path no longer has a mechanical continuous-axis or discrete-air-transaction gap. Remaining work is empirical rather than architectural: physical-controller playtesting, threshold tuning, accessibility tuning, and visual QA across the complete gesture space.

### Animation tuning and visual QA

The procedural animation already exposes the physical system through:

- preload and prewind,
- shoulder-led initiation,
- pelvis follow-through,
- ski lag,
- compact mid-rotation body shape,
- grab-driven asymmetry,
- head/chest spotting,
- visible opening/checking,
- signed underrotation/overrotation landing recovery.

The remaining work here is controller playtesting and visual tuning across the full range of weak, strong, switch, grab, and off-axis takeoffs.

## Final feel test

The trick system is approaching this target when the player can answer these questions by feel rather than by HUD information:

- Did I preload enough rotation?
- What axis did I throw the trick on?
- Am I rotating too slowly or too quickly?
- Should I stay compact or open up?
- Can I still check this landing?
- Am I about to underrotate or overrotate?

A successful trick should feel like the result of a good setup followed by good body management, not the result of asking the game to execute the correct named move.
