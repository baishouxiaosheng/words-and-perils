extends RefCounted
## Player-facing wording only. Signed goals remain unchanged in the engine,
## request, assessment provenance and saves.
const SAMPLE_PREFIX := "【署名样例】"

const RULE_SAMPLE_PREFIX := "【署名规则样例】"
const OTHER_SAMPLE_PREFIXES := ["【署名多地貌样例】","【署名创意样例】","【署名围寨样例】","【署名战斗样例】","【署名物品样例】","【署名NPC反击样例】","【署名场景样例】","【署名复合样例】"]

static func is_signed_sample(text: String) -> bool:
	if text.begins_with(SAMPLE_PREFIX) or text.begins_with(RULE_SAMPLE_PREFIX): return true
	for prefix in OTHER_SAMPLE_PREFIXES:
		if text.begins_with(prefix): return true
	return false

static func player_intent(text: String) -> String:
	if text.begins_with(SAMPLE_PREFIX): return text.substr(SAMPLE_PREFIX.length())
	if text.begins_with(RULE_SAMPLE_PREFIX):
		var words := text.substr(RULE_SAMPLE_PREFIX.length())
		if words.begins_with("尝试放倒关注的树（tree:") and words.ends_with("），让它的归属地面成为阻挡。"):
			return "尝试放倒这株树，挡住它所在的地面。"
		return words
	for prefix in OTHER_SAMPLE_PREFIXES:
		if text.begins_with(prefix):
			var words: String=text.substr(prefix.length())
			var ids:=RegEx.new(); ids.compile("（(?:(?:actor|item|entrance)_[a-zA-Z0-9_]+|gate:[a-zA-Z0-9_:-]+)）")
			return ids.sub(words,"",true)
	return text
