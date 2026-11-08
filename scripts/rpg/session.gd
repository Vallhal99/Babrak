class_name Session
extends RefCounted
## Stav mezi scénami (výběr třídy v menu -> herní scéna).

static var class_id: StringName = &"warrior"
static var pending_load := 0   ## slot, který se má načíst po startu herní scény (0 = nic)
