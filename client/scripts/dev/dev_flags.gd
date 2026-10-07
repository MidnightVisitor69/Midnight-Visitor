extends RefCounted
## Dev-only switches. This file must be flipped back before a release: the holo
## test bench is a developer tool, not a game screen, and must never ship
## enabled (AGENTS.md next task 2, .task.md). Kept as plain consts so a test can
## read the routing decision without swapping scenes.


## Boot straight into the holo test scene instead of the normal main scene.
const START_IN_HOLO_TEST := true
