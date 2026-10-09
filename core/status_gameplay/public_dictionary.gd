extends RefCounted
## Lossless, flat public-data interning. No world reads, effects, code or formulas.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const SCHEMA="public_dictionary/v2"
const FIELD="public_dictionary"
const REF="$p"
const MAX_VALUES=128
const MAX_DEPTH=64
# Maximum serialized {"$p":127} is10 bytes; table key+colon+comma is7.
const REF_BYTES=10
const TABLE_KEY_BYTES=7
const MAX_EXPANDED_BYTES=262144
const MAX_EXPANDED_NODES=16384
const SEMANTICS="Exact {$p:N} resolves values[str(N)], integer0..127. Flat public JSON; goal/focus literal; all history/status restored; no omissions."

static func enabled(request:Dictionary) -> bool:
 return request.has("status_context") and "coast_status_source/v1" in request.get("contract",{}).get("resolver_ids",[])

static func pack(request:Dictionary) -> Dictionary:
 if not C.safe(request):return C.fail("PUBLIC_DICTIONARY_DATA","Only finite public JSON is supported")
 if C.bytes(request).to_utf8_buffer().size()>MAX_EXPANDED_BYTES:return C.fail("PUBLIC_DICTIONARY_BUDGET","Expanded public request exceeds bounded decoder capacity")
 if request.has(FIELD) or _has_ref(request):return {"ok":true,"request":request.duplicate(true),"packed":false}
 var counts:Dictionary={};var values:Dictionary={}
 _collect(request,[],counts,values)
 var candidates:Array=[]
 for key in counts:
  var n:int=counts[key];var size:int=key.to_utf8_buffer().size()
  if n>=2 and (n-1)*size-n*REF_BYTES-TABLE_KEY_BYTES>0:candidates.append(key)
 # Highest net saving first, with canonical-text tie-breaks; local IDs are stable.
 candidates.sort_custom(func(a:String,b:String)->bool:
  var ga:int=(int(counts[a])-1)*a.to_utf8_buffer().size()-int(counts[a])*REF_BYTES-TABLE_KEY_BYTES
  var gb:int=(int(counts[b])-1)*b.to_utf8_buffer().size()-int(counts[b])*REF_BYTES-TABLE_KEY_BYTES
  return ga>gb if ga!=gb else a<b)
 if candidates.size()>MAX_VALUES:candidates.resize(MAX_VALUES)
 var ids:Dictionary={}
 for i in range(candidates.size()):ids[candidates[i]]=i
 var used:Dictionary={}
 var packed:Dictionary=_replace(request,[],ids,used)
 var filtered:Dictionary=_profitable(ids,used)
 # Each retry removes at least one candidate. IDs are then dense, stable and
 # frequency-ranked, and every final entry has positive measured byte gain.
 for _pass in range(MAX_VALUES+1):
  used.clear();packed=_replace(request,[],filtered,used)
  var ordered:Array=filtered.keys()
  ordered.sort_custom(func(a:String,b:String)->bool:
   var na:int=int(used.get(filtered[a],0));var nb:int=int(used.get(filtered[b],0))
   return na>nb if na!=nb else a<b)
  var final_ids:Dictionary={}
  for i in range(ordered.size()):final_ids[ordered[i]]=i
  used.clear();packed=_replace(request,[],final_ids,used)
  var retained:Dictionary=_profitable(final_ids,used)
  filtered=retained
  if retained.size()==final_ids.size():break
 var table:Dictionary={}
 for key in filtered:
  if used.has(filtered[key]):table[str(filtered[key])]=values[key].duplicate(true) if values[key] is Dictionary or values[key] is Array else values[key]
 if table.is_empty():return {"ok":true,"request":request.duplicate(true),"packed":false}
 packed[FIELD]={"schema_version":SCHEMA,"values":table,"expanded_sha256":C.digest(request),"semantics":SEMANTICS}
 if not C.safe(packed):return {"ok":true,"request":request.duplicate(true),"packed":false}
 if C.bytes(packed).to_utf8_buffer().size()>=C.bytes(request).to_utf8_buffer().size():return {"ok":true,"request":request.duplicate(true),"packed":false}
 var restored:=expand(packed)
 if not restored.ok or C.bytes(restored.request)!=C.bytes(request):return C.fail("PUBLIC_DICTIONARY_EQUIVALENCE","Public request could not be restored exactly")
 return {"ok":true,"request":C.normalized(packed),"packed":true,"values":table.size()}

static func _profitable(ids:Dictionary,used:Dictionary) -> Dictionary:
 var retained:Dictionary={}
 for key in ids:
  var n:int=int(used.get(ids[key],0))
  var marker_bytes:int=C.bytes({REF:ids[key]}).to_utf8_buffer().size()
  var table_key_bytes:int=C.bytes(str(ids[key])).to_utf8_buffer().size()+2
  if n>=2 and (n-1)*key.to_utf8_buffer().size()-n*marker_bytes-table_key_bytes>0:retained[key]=ids[key]
 return retained

static func _protected(path:Array) -> bool:
 if path.is_empty():return false
 if path[0]=="context":return path.size()>=2 and path[1]!="facts"
 if path[0]=="contract":return path.size()>=2 and not path[1] in ["action_schemas","control_reply","assessment_reply"]
 # Protocol IDs/hash/phase stay literal. Complete public history and active
 # status data may intern repeated values, with byte-exact expanded equivalence.
 return not path[0] in ["memory_context","status_context"]
static func _collect(value:Variant,path:Array,counts:Dictionary,values:Dictionary) -> void:
 if _protected(path):return
 if path.size()>=2 and (value is Dictionary or value is Array or value is String):
  var key:String=C.bytes(value)
  if key.to_utf8_buffer().size()>REF_BYTES:counts[key]=int(counts.get(key,0))+1;values[key]=value
 if value is Dictionary:
  for key in value:_collect(value[key],path+[key],counts,values)
 elif value is Array:
  for i in range(value.size()):_collect(value[i],path+[str(i)],counts,values)
static func _replace(value:Variant,path:Array,ids:Dictionary,used:Dictionary) -> Variant:
 if _protected(path):return value.duplicate(true) if value is Dictionary or value is Array else value
 if path.size()>=2 and (value is Dictionary or value is Array or value is String):
  var key:String=C.bytes(value)
  if ids.has(key):used[ids[key]]=int(used.get(ids[key],0))+1;return {REF:ids[key]}
 if value is Dictionary:
  var out:Dictionary={}
  for key in value:out[key]=_replace(value[key],path+[key],ids,used)
  return out
 if value is Array:
  var out:Array=[]
  for i in range(value.size()):out.append(_replace(value[i],path+[str(i)],ids,used))
  return out
 return value
static func _has_ref(value:Variant) -> bool:
 if value is Dictionary:
  if value.has(REF):return true
  for item in value.values():
   if _has_ref(item):return true
 elif value is Array:
  for item in value:
   if _has_ref(item):return true
 return false

static func expand(request:Dictionary) -> Dictionary:
 if not C.safe(request):return C.fail("PUBLIC_DICTIONARY_DATA","Unsafe encoded public request")
 if not request.has(FIELD):return {"ok":true,"request":request.duplicate(true)}
 var descriptor:Variant=request[FIELD]
 if not C.exact_fields(descriptor,["schema_version","values","expanded_sha256","semantics"]) or descriptor.schema_version!=SCHEMA or descriptor.semantics!=SEMANTICS or not descriptor.values is Dictionary or descriptor.values.is_empty() or descriptor.values.size()>MAX_VALUES or not descriptor.expanded_sha256 is String or descriptor.expanded_sha256.length()!=64:return C.fail("PUBLIC_DICTIONARY_SCHEMA","Unknown public dictionary contract")
 for character in descriptor.expanded_sha256:
  if not character in "0123456789abcdef":return C.fail("PUBLIC_DICTIONARY_HASH","Invalid expanded digest")
 if not _valid_table(descriptor.values):return C.fail("PUBLIC_DICTIONARY_REFERENCE","Only canonical integer keys and flat finite public values are valid")
 var raw:Dictionary=request.duplicate(true);raw.erase(FIELD)
 var decoded:=expand_value(raw,descriptor.values)
 if not decoded.ok:return decoded
 if not decoded.value is Dictionary or not C.safe(decoded.value) or C.digest(decoded.value)!=descriptor.expanded_sha256:return C.fail("PUBLIC_DICTIONARY_HASH","Expanded public request differs from its frozen digest")
 return {"ok":true,"request":decoded.value}

static func expand_value(value:Variant,table:Dictionary,depth:int=0,max_bytes:int=MAX_EXPANDED_BYTES) -> Dictionary:
 if depth<0 or depth>MAX_DEPTH or max_bytes<0 or max_bytes>MAX_EXPANDED_BYTES or not C.safe(value):return C.fail("PUBLIC_DICTIONARY_DATA","Invalid bounded public reference value")
 if not _valid_table(table):return C.fail("PUBLIC_DICTIONARY_REFERENCE","Invalid bounded flat public table")
 var cache:Dictionary={}
 var measured:=_shape(value,table,cache,depth,max_bytes,MAX_EXPANDED_NODES)
 if not measured.ok:return measured
 var decoded:Variant=_decode(value,table)
 if not C.safe(decoded):return C.fail("PUBLIC_DICTIONARY_DATA","Expanded data is unsafe")
 return {"ok":true,"value":decoded,"expanded_bytes":measured.bytes,"expanded_nodes":measured.nodes}

static func _valid_table(table:Dictionary) -> bool:
 if table.size()>MAX_VALUES:return false
 for id in table:
  if not id is String or id.length()>3 or not id.is_valid_int() or id!=str(int(id)) or int(id)<0 or int(id)>=MAX_VALUES or not C.safe(table[id]) or _has_ref(table[id]):return false
 return true

static func _shape(value:Variant,table:Dictionary,cache:Dictionary,depth:int,bytes_left:int,nodes_left:int) -> Dictionary:
 if depth>MAX_DEPTH or bytes_left<0 or nodes_left<1:return C.fail("PUBLIC_DICTIONARY_BUDGET","Reference expansion exceeds fixed byte/node/depth budget")
 if value is Dictionary and value.has(REF):
  if not C.exact_fields(value,[REF]) or not C.integer(value[REF]) or int(value[REF])<0 or int(value[REF])>=MAX_VALUES or not table.has(str(int(value[REF]))):return C.fail("PUBLIC_DICTIONARY_REFERENCE","Dangling or ambiguous public reference")
  var id:String=str(int(value[REF]))
  if not cache.has(id):
   var raw:Variant=table[id]
   if not C.safe(raw) or _has_ref(raw):return C.fail("PUBLIC_DICTIONARY_REFERENCE","Nonfinite or recursive dictionary value")
   var measure:=_shape(raw,{}, {},0,MAX_EXPANDED_BYTES,MAX_EXPANDED_NODES)
   if not measure.ok:return measure
   cache[id]=measure
  var known:Dictionary=cache[id]
  if known.bytes>bytes_left or known.nodes>nodes_left or depth+known.height>MAX_DEPTH:return C.fail("PUBLIC_DICTIONARY_BUDGET","Reference expansion exceeds fixed byte/node/depth budget")
  return known.duplicate(true)
 var size:=2;var nodes:=1;var height:=0
 if value is Dictionary:
  var first:=true
  for key in value:
   size+=C.bytes(String(key)).to_utf8_buffer().size()+1+(0 if first else 1);first=false
   var child:=_shape(value[key],table,cache,depth+1,bytes_left-size,nodes_left-nodes)
   if not child.ok:return child
   size+=child.bytes;nodes+=child.nodes;height=maxi(height,1+int(child.height))
 elif value is Array:
  var first:=true
  for item in value:
   size+=0 if first else 1;first=false
   var child:=_shape(item,table,cache,depth+1,bytes_left-size,nodes_left-nodes)
   if not child.ok:return child
   size+=child.bytes;nodes+=child.nodes;height=maxi(height,1+int(child.height))
 else:size=C.bytes(value).to_utf8_buffer().size()
 if size>bytes_left or nodes>nodes_left:return C.fail("PUBLIC_DICTIONARY_BUDGET","Reference expansion exceeds fixed byte/node budget")
 return {"ok":true,"bytes":size,"nodes":nodes,"height":height}

static func _decode(value:Variant,table:Dictionary) -> Variant:
 if value is Dictionary:
  if value.has(REF):
   var raw:Variant=table[str(int(value[REF]))]
   return raw.duplicate(true) if raw is Dictionary or raw is Array else raw
  var out:Dictionary={}
  for key in value:out[key]=_decode(value[key],table)
  return out
 if value is Array:
  var out:Array=[]
  for item in value:out.append(_decode(item,table))
  return out
 return value
