extends Node3D
## A decoy flare: missiles that see it may switch to chasing it instead of the aircraft.

var p := Vector3.ZERO
var v := Vector3.ZERO
var age := 0.0
var owner_v = null
var glow: Sprite3D
var smoke: CPUParticles3D
