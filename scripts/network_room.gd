extends Node
## Realtime room transport. Godot Web exports may use WebSocketPeer as clients.
signal session_ready(data: Dictionary)
signal state_received(state: Dictionary)
signal message_received(packet: Dictionary)
signal connection_status(message: String)

const STORAGE := "user://ergolab_identity.json"
var socket: WebSocketPeer = WebSocketPeer.new()
var request: HTTPRequest
var room: String = ""
var peer_id: String = ""
var token: String = ""
var role: String = ""
var last_seq: int = 0
var connected: bool = false
var connecting: bool = false
var retry_seconds: float = 0.0
var ping_seconds: float = 0.0
var endpoint: String = ""
var server_origin: String = ""

func _ready() -> void:
    request = HTTPRequest.new()
    request.timeout = 18.0
    add_child(request)
    request.request_completed.connect(_on_http_done)
    if OS.has_feature("web"):
        server_origin = str(JavaScriptBridge.eval("window.location.origin"))
    else:
        server_origin = "http://localhost:3000"
    endpoint = server_origin.replace("https://", "wss://").replace("http://", "ws://") + "/api/ws"

func room_from_url() -> String:
    if OS.has_feature("web"):
        return str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('s') || ''"))
    return ""

func has_room() -> bool:
    return not room.is_empty() and not token.is_empty()

func my_avatar_uid() -> int:
    return absi(peer_id.hash()) + 900000000

func start_new(nickname: String, color: String) -> void:
    _http_request({"action":"create", "nickname":nickname,"color":color})

func enter_room(room_code: String, nickname: String, color: String) -> void:
    var stored: Dictionary = _read_identity()
    var identities: Dictionary = stored.get("rooms", {})
    var old: Dictionary = identities.get(room_code, {})
    if not str(old.get("token", "")).is_empty():
        _http_request({"action":"resume", "room":room_code, "id":old.get("id", ""), "token":old.get("token", "")})
    else:
        _http_request({"action":"join", "room":room_code, "nickname":nickname,"color":color})

func _http_request(payload: Dictionary) -> void:
    if request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
        connection_status.emit("Une connexion est déjà en cours")
        return
    var headers := PackedStringArray(["Content-Type: application/json"])
    var error := request.request(server_origin + "/api/session", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
    if error != OK:
        connection_status.emit("Erreur de connexion HTTP : " + str(error))
    else:
        connection_status.emit("Connexion à la salle en cours…")

func _on_http_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
    var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
    if code != 200 or not (parsed is Dictionary):
        connection_status.emit("Connexion refusée : " + str(parsed.get("error", code) if parsed is Dictionary else code))
        return
    room = str(parsed.get("room", ""))
    peer_id = str(parsed.get("id", ""))
    token = str(parsed.get("token", ""))
    role = str(parsed.get("role", "participant"))
    var stored: Dictionary = _read_identity()
    var identities: Dictionary = stored.get("rooms", {})
    identities[room] = {"id":peer_id,"token":token}
    _store_identity({"rooms":identities,"last_room":room})
    session_ready.emit(parsed)
    _connect_ws()

func _read_identity() -> Dictionary:
    # Share the anonymous identity with the web dashboard on the same origin.
    if OS.has_feature("web"):
        var raw: Variant = JavaScriptBridge.eval("window.localStorage.getItem('ergolab-room-identity-v2') || ''")
        if raw is String and not raw.is_empty():
            var identity: Variant = JSON.parse_string(raw)
            if identity is Dictionary and identity.has("room") and identity.has("token"):
                var room_id := str(identity.get("room", ""))
                return {"rooms":{room_id:{"id":identity.get("id", ""),"token":identity.get("token", "")}}}
    if not FileAccess.file_exists(STORAGE):
        return {}
    var f := FileAccess.open(STORAGE, FileAccess.READ)
    if f == null:
        return {}
    var data: Variant = JSON.parse_string(f.get_as_text())
    if not (data is Dictionary):
        return {}
    if data.has("room") and data.has("token"):
        return {"rooms":{str(data.get("room","")):{"id":data.get("id",""),"token":data.get("token","")}}}
    return data

func _store_identity(data: Dictionary) -> void:
    if OS.has_feature("web") and not room.is_empty():
        var transfer := {"room":room,"id":peer_id,"token":token,"role":role}
        var encoded := JSON.stringify(JSON.stringify(transfer))
        JavaScriptBridge.eval("window.localStorage.setItem('ergolab-room-identity-v2', " + encoded + ")")
    var f := FileAccess.open(STORAGE, FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify(data))
        f.close()

func _connect_ws() -> void:
    if not has_room() or connecting:
        return
    socket = WebSocketPeer.new()
    connecting = true
    var err := socket.connect_to_url(endpoint)
    if err != OK:
        connecting = false
        retry_seconds = 3.0
        connection_status.emit("WebSocket indisponible : " + str(err))

func _process(delta: float) -> void:
    if not has_room():
        return
    socket.poll()
    var state := socket.get_ready_state()
    if state == WebSocketPeer.STATE_OPEN:
        if connecting:
            connecting = false
            connected = true
            retry_seconds = 0.0
            _send({"op":"hello","room":room,"id":peer_id,"token":token})
            connection_status.emit("Synchronisation de la salle…")
        ping_seconds += delta
        if ping_seconds > 12.0:
            ping_seconds = 0.0
            _send({"op":"ping"})
        while socket.get_available_packet_count() > 0:
            var pkt: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
            if pkt is Dictionary:
                _on_packet(pkt)
    elif state == WebSocketPeer.STATE_CLOSED:
        if connected or connecting:
            connected = false
            connecting = false
            retry_seconds = 2.0
            connection_status.emit("Connexion perdue. Reconnexion automatique…")
        elif retry_seconds > 0.0:
            retry_seconds -= delta
            if retry_seconds <= 0.0:
                _connect_ws()

func _on_packet(packet: Dictionary) -> void:
    var kind: String = str(packet.get("kind", ""))
    if kind == "welcome" or kind == "snapshot":
        last_seq = maxi(last_seq, int(packet.get("cursor", 0)))
        var state: Variant = packet.get("state", {})
        if state is Dictionary:
            state_received.emit(state)
        connection_status.emit("Salle " + room + " · synchronisée")
        return
    if kind == "error":
        connection_status.emit(str(packet.get("message", "Erreur réseau")))
        if str(packet.get("message", "")).contains("Conflit"):
            _send({"op":"refresh"})
        return
    if kind == "pong":
        return
    var seq: int = int(packet.get("seq", 0))
    if seq <= last_seq:
        return
    last_seq = seq
    message_received.emit(packet)

func _send(data: Dictionary) -> void:
    if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        socket.send_text(JSON.stringify(data))

func send_move(x: float, y: float) -> void:
    if connected:
        _send({"op":"move","x":x,"y":y})

func send_interaction(action: String, target: int = -1) -> void:
    if connected:
        _send({"op":"interact","action":action,"target":target})

func send_layout(scenarios: Array, current: int, revision: int) -> void:
    if connected:
        _send({"op":"layout","scenarios":scenarios,"active_index":current,"revision":revision})

func send_pause(value: bool) -> void:
    if connected:
        _send({"op":"pause","value":value})

func send_lock(value: bool) -> void:
    if connected:
        _send({"op":"lock","value":value})

func copy_link() -> void:
    if not room.is_empty():
        DisplayServer.clipboard_set(server_origin + "/?s=" + room)
