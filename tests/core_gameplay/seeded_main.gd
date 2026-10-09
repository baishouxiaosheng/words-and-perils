extends "res://main.gd"
## Only the test factory is deterministic. The same release calculator and real
## program RNG run every check; no forced result, world patch or production seed.
const TestAdapter=preload("res://view/playable_build/adapter.gd")
var journey_seed := -1
func new_coast_adventure() -> RefCounted:
	if journey_seed<0:
		for candidate in range(1,1000):
			var rng:=RandomNumberGenerator.new();rng.seed=candidate
			var fits:=true
			for i in range(6):
				if rng.randi_range(1,10000)>6000:fits=false;break
			if fits:journey_seed=candidate;break
	print("HONEST_RELEASE_TEST_SEED ",journey_seed)
	return TestAdapter.new(journey_seed,true)
