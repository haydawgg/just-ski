# Post-Initial-Decomposition Baseline

> Historical baseline. The uncapped current-tree refresh, isolation evidence, and active comparison contract are in `docs/PERFORMANCE_BASELINE_1080P.md`. The earlier ~15 FPS result below was caused by a non-comparable capped cadence and must not be used as the current performance reference.

This is the named stabilization baseline for future refactors. It is intentionally a **post-initial-decomposition baseline**: the first animation, camera, and skier helper seams landed before this measurement point, so these numbers cannot prove complete numerical equivalence between `820def3` and `56f858`.

## Identity and environment

- Baseline commit: `16426398c68ab4e0fd14063a490cc8c6bb0adf57` (`Stabilize CI and add profile-gated GI settings`).
- Capture date: 2026-09-01.
- Godot: `4.7.2.stable.official.ed1daf0bf`.
- OS: Windows 11 Pro, build `10.0.26200`.
- CPU: 12th Gen Intel Core i7-12650H.
- GPU: NVIDIA GeForce RTX 4050 Laptop GPU, driver `32.0.16.1074`.
- Display configuration source: `project.godot`, 1920×1080 viewport/window override, fullscreen startup.

The baseline commit passed the clean-style local static and runtime gate. The hosted Quality Gate reference for that commit is [run 33542265475](https://github.com/haydawgg/just-ski/actions/runs/33542265475); its result is tracked separately while the hosted Windows job completes. The profiling extension was then run locally with the same isolated-user-directory discipline and the complete runtime scene list also passed.

## Gameplay reference outputs

Values below are representative outputs from the maintained acceptance scenes, not universal design limits.

| Scenario | Measurement |
| --- | --- |
| Ground acceleration | `0.000 → 8.114 m/s` |
| Braking | `3.774 → 1.814 m/s` |
| Gameplay carve | `3.721 m/s` start, `6.862 m/s` end, `1.613 m` lateral travel, `32.056°` heading |
| Gameplay pop | `1.346 m` apex, `1.017 s` airtime |
| Physics pop benchmark | `1.762 m` apex, `1.133 s` airtime, `7.07 m/s` landing speed |
| Left 360 benchmark | `6.43 m/s` takeoff, `6.71 m/s` landing, `1.083 s` air, `1.566 m` peak, `342°` spin |
| Landing outcomes | Pop `CLEAN / 0.951 / 4.801 m/s`; trick `CLEAN / 0.879 / 4.662 m/s`; grab `CLEAN / 0.951 / 4.801 m/s` |
| Rail animation sample | pelvis `0.0286`, ski `0.0695`, shoulder `0.0332` deltas |

The quality value remains a continuous point-scaling/feedback value; the outcome is the authoritative clean/sketchy/hard classification.

## Camera and runtime performance

Camera measurements came from the 30/60/120 Hz camera acceptance scenes on the reference laptop:

| Rate | Average update | Maximum frame sample |
| --- | ---: | ---: |
| 30 Hz | `695.93 µs` | `1030 µs` |
| 60 Hz | `692.19 µs` | `1060 µs` |
| 120 Hz | `701.18 µs` | `1390 µs` |

All three rates reported zero fallbacks. Phase samples were:

| Phase | Average | Max | Shape queries | Ray queries | Composition evaluations |
| --- | ---: | ---: | ---: | ---: | ---: |
| Ground | `668.17 µs` | `701 µs` | 132 | 222 | 12 |
| Air | `1701.57 µs` | `2726 µs` | 1510 | 3307 | 897 |
| Landing | `668.23 µs` | `710 µs` | 330 | 546 | 30 |
| Rail | `665.00 µs` | `815 µs` | 330 | 546 | 30 |
| Crash | `1814.17 µs` | `1889 µs` | 2760 | 7626 | 540 |

The first profiling pass measured rail scaling with four-point paths:

| Rails | Build | Query | Average query |
| ---: | ---: | ---: | ---: |
| 8 | `24.17 ms` | `0.52 ms` | `2.15 µs` |
| 32 | `88.17 ms` | `2.07 ms` | `2.16 µs` |
| 64 | `179.00 ms` | `4.11 ms` | `2.14 µs` |

The sampled rail query locations intentionally produced zero valid captures; these are runtime-cost measurements, not rail-validity assertions.

World construction/session profiling reported `401.64 ms` construction, `23.37 ms` first-frame work, `7.92 ms` average and `8.61 ms` maximum over the sampled session frames, `148,585,967` bytes of static memory, and `7,568` child nodes.

## Snow/GPU and audio profiling

The visual profile was a non-headless run on the reference NVIDIA laptop. The measured average render cadence was about 15 FPS in both tiers; these values are diagnostic observations, not CI thresholds.

| Snow tier | Average FPS | Average frame | Objects | Primitives | Draw calls | Video memory | Texture memory | Buffer memory |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Fast | `14.9834` | `66.7404 ms` | 1450 | 350,872 | 1134 | 881,052,496 | 687,523,328 | 73,910,104 |
| Premium | `15.0091` | `66.6262 ms` | 1450 | 370,072 | 1134 | 916,472,464 | 722,912,768 | 73,943,128 |

Audio process timing was sampled by the same visual profile:

| Snow tier | Samples | Average | Maximum | Total |
| --- | ---: | ---: | ---: | ---: |
| Fast | 77 | `7528.68 µs` | `14367 µs` | `579708 µs` |
| Premium | 78 | `8402.05 µs` | `24608 µs` | `655360 µs` |

The headless profiling acceptance scene reports zero audio samples because the isolated CI-style run has no audio device; the non-headless visual profile supplies the representative audio-process sample.

## Clip capture memory

The MP4 diagnostic built and JPEG-encoded 450 frames at 960×540 in `3594 ms`, then muxed `14,084,968` bytes in `36 ms`. Static-memory samples were:

- before capture: `59,360,749` bytes;
- after frame capture: `73,483,874` bytes, a `14,123,125` byte delta;
- after encode: `94,608,136` bytes, a `21,124,262` byte delta from the capture sample.

These are point-in-time samples and should be repeated under longer captures before making memory or recorder changes.

## Accepted unresolved items

- No physical controller was attached during this baseline. Xbox/PlayStation identification, multi-controller hotplug, rumble delivery, and stick feel still require the physical procedure in `CONTROLLER_VALIDATION.md`.
- Headless audio timing is unavailable by design; non-headless timing is documented above.
- GPU measurements are reference-laptop observations and are not portable pass/fail thresholds for hosted CI.
- The initial decomposition commit predates this baseline, so this document does not silently claim numerical equivalence across that architectural boundary.
- Subjective camera comfort, long-session ski feel, visual intersections, final secondary-motion tuning, and production-art readiness remain the human-review items listed in `KNOWN_ISSUES.md`.
