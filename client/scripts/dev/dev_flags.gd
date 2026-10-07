extends RefCounted
## Dev-only switches. This file must be flipped back before a release: the holo
## test bench is a developer tool, not a game screen, and must never ship
## enabled. Since T-005 the app shell is the default boot path and the bench is
## reached from the shell's top bar in debug builds. Kept as a plain const so a
## test can read the routing decision without swapping scenes.


## Boot straight into the holo test scene instead of the app shell.
const START_IN_HOLO_TEST := false
