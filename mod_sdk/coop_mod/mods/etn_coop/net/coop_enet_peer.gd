extends MultiplayerPeerExtension

## 保留 ENet 原生通道/可靠性与 SceneMultiplayer 转发协议。
## 原生 poll 的断线信号栈里其他 ENet peer 可能已无通道但尚未出表。
## 先汇总本次 poll 的事件，再通知 SceneMultiplayer；发送只面向仍连接的底层 peer。
var _enet := ENetMultiplayerPeer.new()
var _peers: Dictionary = {} # id -> ENetPacketPeer；只在原生连接信号中取引用
var _admitted: Dictionary = {}
var _events: Array = []
var _incoming: Array = []
var _read_index := 0
var _unique_id := 0
var _server := false
var _target := 0

func _init():
	_enet.peer_connected.connect(_on_connected)
	_enet.peer_disconnected.connect(_on_disconnected)

func create_server(port: int, max_clients: int) -> Error:
	var err := _enet.create_server(port, max_clients)
	if err == OK:
		_unique_id = _enet.get_unique_id()
		_server = true
	return err

func create_client(ip: String, port: int) -> Error:
	var err := _enet.create_client(ip, port)
	if err == OK:
		_unique_id = _enet.get_unique_id()
		_server = false
	return err

func _on_connected(id: int):
	_peers[id] = _enet.get_peer(id)
	_events.append({"id": id, "connected": true})

func _on_disconnected(id: int):
	_peers.erase(id)
	_incoming = _incoming.slice(_read_index).filter(func(packet): return int(packet.peer) != id)
	_read_index = 0
	if _admitted.has(id):
		_events.append({"id": id, "connected": false})
	else:
		# 同一次 poll 里连接后立刻断开，从未向 SceneMultiplayer 准入。
		_events = _events.filter(func(event): return int(event.id) != id)

func _poll() -> void:
	if _enet.get_connection_status() == CONNECTION_DISCONNECTED:
		return
	_enet.poll()
	while _enet.get_available_packet_count() > 0:
		var id := _enet.get_packet_peer()
		var channel := _enet.get_packet_channel()
		var mode := _enet.get_packet_mode()
		var data := _enet.get_packet()
		if _can_send(id):
			_incoming.append({"peer": id, "channel": channel, "mode": mode, "data": data})
	var events := _events.duplicate()
	_events.clear()
	for event in events:
		var id: int = event.id
		if event.connected:
			if _can_send(id) and not _admitted.has(id):
				_admitted[id] = true
				peer_connected.emit(id)
		else:
			# 强制断开时原生 peer_disconnected 与手动通知可能在同一 poll 各排一次事件；
			# 先出表即视为重复，跳过以免 peer_disconnected 双发。
			if not _admitted.has(id):
				continue
			_admitted.erase(id)
			peer_disconnected.emit(id)

func _can_send(id: int) -> bool:
	var peer = _peers.get(id)
	return peer != null and peer.get_state() == ENetPacketPeer.STATE_CONNECTED

func _put_packet_script(data: PackedByteArray) -> Error:
	if _enet.get_connection_status() != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if not _server:
		if not _can_send(1): return ERR_UNAVAILABLE
		_enet.set_target_peer(1)
		return _enet.put_packet(data)
	if _target > 0:
		if not _can_send(_target): return ERR_UNAVAILABLE
		_enet.set_target_peer(_target)
		return _enet.put_packet(data)
	var result := OK
	for id in _peers:
		if (_target < 0 and id == -_target) or not _can_send(id): continue
		_enet.set_target_peer(id)
		var err := _enet.put_packet(data)
		if err != OK: result = err
	return result

func _get_available_packet_count() -> int:
	return _incoming.size() - _read_index

func _get_packet_script() -> PackedByteArray:
	if _read_index >= _incoming.size(): return PackedByteArray()
	var data: PackedByteArray = _incoming[_read_index].data
	_read_index += 1
	if _read_index == _incoming.size():
		_incoming.clear()
		_read_index = 0
	return data

func _get_packet_peer() -> int:
	return int(_incoming[_read_index].peer) if _read_index < _incoming.size() else 0

func _get_packet_channel() -> int:
	return int(_incoming[_read_index].channel) if _read_index < _incoming.size() else 0

func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _incoming[_read_index].mode if _read_index < _incoming.size() else TRANSFER_MODE_RELIABLE

func _get_unique_id() -> int: return _unique_id
func _get_connection_status() -> MultiplayerPeer.ConnectionStatus: return _enet.get_connection_status()
func _get_max_packet_size() -> int: return 1 << 24
func _set_target_peer(id: int) -> void: _target = id
func _get_transfer_channel() -> int: return _enet.get_transfer_channel()
func _get_transfer_mode() -> MultiplayerPeer.TransferMode: return _enet.get_transfer_mode()
func _set_transfer_channel(channel: int) -> void: _enet.set_transfer_channel(channel)
func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void: _enet.set_transfer_mode(mode)
func _is_server() -> bool: return _server
func _is_server_relay_supported() -> bool: return true
func _is_refusing_new_connections() -> bool: return _enet.is_refusing_new_connections()
func _set_refuse_new_connections(enabled: bool) -> void: _enet.set_refuse_new_connections(enabled)
func _disconnect_peer(id: int, force: bool) -> void:
	if _can_send(id):
		_enet.disconnect_peer(id, force)
		if force: _on_disconnected(id)

func _close() -> void:
	_enet.close()
	_peers.clear()
	_admitted.clear()
	_events.clear()
	_incoming.clear()
	_read_index = 0
	_unique_id = 0
