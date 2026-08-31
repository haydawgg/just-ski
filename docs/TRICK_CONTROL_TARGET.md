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

The project is already moving toward this target.

Implemented or underway:

- preload depth, duration, and release speed contribute to takeoff quality,
- the minimum effective takeoff strength has been lowered so weak setups remain meaningfully weak,
- spin and cork authority is committed at takeoff,
- takeoff rotation is distributed across a short release window instead of arriving as one instantaneous impulse,
- neutral airborne spin/cork flicks are rejected,
- airborne continuation/check authority is finite,
- precision air trim has been reduced so it cannot substitute for takeoff technique,
- signed rotation residuals and stricter completion thresholds exist,
- a persistent `TrickRotationState` exists for reference-frame progress, release state, compactness, inertia, and future assist accounting,
- a quaternion air-rotation integrator exists and has acceptance coverage,
- compactness/inertia behavior has deterministic test coverage,
- trick rotation benchmark and live control regression tests have been added.

## Remaining gaps

The target is not complete yet.

### Live controller integration

`SkierController` still needs to use the new rotation state as the authoritative live model.

That includes:

- quaternion orientation integration,
- takeoff-reference-frame rotation progress,
- gameplay-owned compactness/inertia affecting live angular velocity,
- authoritative signed residuals feeding landing and animation,
- removal or reduction of unexplained late-air automatic damping.

### Flip controls

Flips are still on the legacy airborne initiation path because the current down-to-up preload gesture already owns straight pop.

A proper preload-compatible flip control must be designed so flips obey the same rule as spins and corks without making straight pop awkward or ambiguous.

### Continuous trick axes

Cork geometry should be derived continuously from the release vector rather than using a fixed yaw/roll ratio.

Eventually spin, flip, and cork should behave more like regions of one continuous rotational space instead of completely separate canned axes.

### Continuous airborne body management

The current continuation/check command system is an important guardrail against airborne trick spam, but the final feel should become more continuous.

The end state should rely more on:

- current stick/body input,
- body compactness,
- effective inertia,
- existing angular momentum,
- remaining airtime,

and less on repeated discrete airborne flick transactions.

### Animation

The procedural animation should explain the physical system through:

- preload and prewind,
- shoulder-led initiation,
- pelvis follow-through,
- ski lag,
- compact mid-rotation body shape,
- grab-driven asymmetry,
- head/chest spotting,
- visible opening/checking,
- signed underrotation/overrotation landing recovery.

## Final feel test

The trick system is approaching this target when the player can answer these questions by feel rather than by HUD information:

- Did I preload enough rotation?
- What axis did I throw the trick on?
- Am I rotating too slowly or too quickly?
- Should I stay compact or open up?
- Can I still check this landing?
- Am I about to underrotate or overrotate?

A successful trick should feel like the result of a good setup followed by good body management, not the result of asking the game to execute the correct named move.
