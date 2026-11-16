extends Control
## Plan de travail en coordonnées de la page 5 (PDF rendu à 145 DPI).
## La diagonale architecturale cotée 14,20 m sert de calibration : 608 px / 14,2 m.

signal selection_changed(item: Dictionary)
signal content_changed()
signal pointer_changed(world_position: Vector2)
signal avatar_motion(x: float, y: float)

const SOURCE_SIZE := Vector2(1571.0, 1088.0)
const PIXELS_PER_METER := 42.82
const COLOR_ACCENT := Color("D56C3E")
const COLOR_INK := Color("24343C")

var catalog: Array = []
var catalog_by_id: Dictionary = {}
var textures: Dictionary = {}
var source_texture: Texture2D
var objects: Array = []
var view_zoom: float = 0.52
var view_origin := Vector2(26.0, 26.0)
var selected_uid: int = -1
var dragging: bool = false
var panning: bool = false
var mouse_anchor := Vector2.ZERO
var drag_anchor := Vector2.ZERO
var grid_enabled: bool = true
var simulation_mode: bool = false
var show_trails: bool = true
var next_uid: int = 1
var multiplayer_mode: bool = false
var local_avatar_uid: int = -1
var may_edit_equipment: bool = true
var room_paused: bool = false
var avatar_speed: float = 60.0
var motion_cooldown: float = 0.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_ALL
    source_texture = load("res://assets/plan_original.png")
    for entry in catalog:
        catalog_by_id[entry["id"]] = entry
        var path: String = "res://assets/equipment/%s.png" % entry["id"]
        if ResourceLoader.exists(path):
            textures[entry["id"]] = load(path)
    resized.connect(_on_resized)
    call_deferred("fit_to_view")

func _on_resized() -> void:
    queue_redraw()

func fit_to_view() -> void:
    if size.x <= 0 or size.y <= 0:
        return
    view_zoom = minf((size.x - 44.0) / SOURCE_SIZE.x, (size.y - 44.0) / SOURCE_SIZE.y)
    view_zoom = clampf(view_zoom, 0.12, 3.5)
    view_origin = (size - SOURCE_SIZE * view_zoom) * 0.5
    queue_redraw()

func zoom_by(factor: float) -> void:
    zoom_at(size * 0.5, factor)

func zoom_at(anchor: Vector2, factor: float) -> void:
    var old_world := to_world(anchor)
    view_zoom = clampf(view_zoom * factor, 0.12, 3.5)
    view_origin = anchor - old_world * view_zoom
    queue_redraw()

func to_world(point: Vector2) -> Vector2:
    return (point - view_origin) / view_zoom

func to_screen(point: Vector2) -> Vector2:
    return point * view_zoom + view_origin

func set_catalog(entries: Array) -> void:
    catalog = entries
    catalog_by_id.clear()
    textures.clear()
    for entry in entries:
        catalog_by_id[entry["id"]] = entry
        var path: String = "res://assets/equipment/%s.png" % entry["id"]
        if ResourceLoader.exists(path):
            textures[entry["id"]] = load(path)
    queue_redraw()

func set_objects(new_objects: Array) -> void:
    objects = new_objects.duplicate(true)
    selected_uid = -1
    next_uid = 1
    for entry in objects:
        next_uid = maxi(next_uid, int(entry.get("uid", 0)) + 1)
    selection_changed.emit({})
    queue_redraw()

func export_objects() -> Array:
    var result: Array = []
    for obj in objects:
        if multiplayer_mode and str(obj.get("type", "")) == "avatar":
            continue
        result.append(obj.duplicate(true))
    return result

func set_live_objects(layout: Array, participants: Array, my_uid: int, editable: bool, paused: bool) -> void:
    multiplayer_mode = true
    local_avatar_uid = my_uid
    may_edit_equipment = editable
    room_paused = paused
    var merged: Array = layout.duplicate(true)
    for p in participants:
        var avatar: Dictionary = p.get("avatar", {})
        merged.append({"uid":int(p.get("uid", -1)),"type":"avatar", "name":str(p.get("nickname","Agent")),
            "x":float(avatar.get("x",980)),"y":float(avatar.get("y",440)),
            "rot":0.0,"color":str(p.get("color","#3C82B5")),"trail":avatar.get("trail",[]),
            "action":str(avatar.get("action","libre")),"connected":bool(p.get("connected",true))})
    objects = merged
    next_uid = 1
    for obj in objects:
        if str(obj.get("type","")) != "avatar":
            next_uid = maxi(next_uid,int(obj.get("uid",0))+1)
    queue_redraw()

func update_live_avatar(uid: int, x: float, y: float, action: String = "", trail: Array = []) -> void:
    var idx := _index_by_uid(uid)
    if idx < 0:
        return
    var obj: Dictionary = objects[idx]
    obj["x"] = x
    obj["y"] = y
    if not action.is_empty():
        obj["action"] = action
    if not trail.is_empty():
        obj["trail"] = trail
    objects[idx] = obj
    queue_redraw()

func update_equipment_position(uid: int, x: float, y: float) -> void:
    var idx := _index_by_uid(uid)
    if idx >= 0:
        objects[idx]["x"] = x
        objects[idx]["y"] = y
        queue_redraw()

func set_live_action(uid: int, action: String) -> void:
    var idx := _index_by_uid(uid)
    if idx >= 0:
        objects[idx]["action"] = action
        queue_redraw()

func nearest_equipment_uid() -> int:
    var mine := _index_by_uid(local_avatar_uid)
    if mine < 0:
        return -1
    var here := Vector2(float(objects[mine]["x"]), float(objects[mine]["y"]))
    var nearest: int = -1
    var dist: float = 140.0
    for o in objects:
        if str(o.get("type")) == "avatar":
            continue
        var d: float = here.distance_to(Vector2(float(o["x"]),float(o["y"])))
        if d < dist:
            nearest = int(o["uid"])
            dist = d
    return nearest

func _avatar_collision(destination: Vector2) -> bool:
    for obj in objects:
        if str(obj.get("type", "")) == "avatar":
            continue
        var center := Vector2(float(obj.get("x",0)),float(obj.get("y",0)))
        var local: Vector2 = (destination - center).rotated(-deg_to_rad(float(obj.get("rot",0))))
        var half := _get_size(obj)*0.5 + Vector2(11,11)
        if absf(local.x) < half.x and absf(local.y) < half.y:
            return true
    return false

func _process(delta: float) -> void:
    if not multiplayer_mode or room_paused or local_avatar_uid < 0 or not has_focus():
        return
    var axis := Vector2.ZERO
    if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A): axis.x -= 1
    if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): axis.x += 1
    if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W): axis.y -= 1
    if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S): axis.y += 1
    if axis.is_zero_approx():
        return
    var idx := _index_by_uid(local_avatar_uid)
    if idx < 0:
        return
    var obj: Dictionary = objects[idx]
    var previous := Vector2(float(obj["x"]),float(obj["y"]))
    var action: String = str(obj.get("action","libre"))
    var speed: float = avatar_speed
    if action == "porter": speed = 46.0
    if action == "pousser": speed = 36.0
    var destination := previous + axis.normalized()*speed*delta
    destination.x = clampf(destination.x,20.0,SOURCE_SIZE.x-20.0)
    destination.y = clampf(destination.y,80.0,SOURCE_SIZE.y-22.0)
    if _avatar_collision(destination):
        return
    obj["x"] = destination.x
    obj["y"] = destination.y
    _record_avatar_trail(obj, destination)
    objects[idx] = obj
    motion_cooldown -= delta
    if motion_cooldown <= 0.0:
        motion_cooldown = 0.14
        avatar_motion.emit(destination.x,destination.y)
    queue_redraw()

func _record_avatar_trail(obj: Dictionary, point: Vector2) -> void:
    if not simulation_mode:
        return
    var trail: Array = obj.get("trail", [])
    if trail.is_empty() or Vector2(float(trail.back()[0]),float(trail.back()[1])).distance_to(point)>12:
        trail.append([point.x,point.y])
    obj["trail"] = trail


func add_equipment(type_id: String) -> void:
    if not catalog_by_id.has(type_id) or (multiplayer_mode and not may_edit_equipment):
        return
    var middle := to_world(size * 0.5)
    var jitter: float = float((next_uid % 5) * 26)
    var obj := {
        "uid": next_uid, "type": type_id,
        "x": clampf(middle.x + jitter, 40.0, SOURCE_SIZE.x - 40.0),
        "y": clampf(middle.y + jitter, 90.0, SOURCE_SIZE.y - 40.0),
        "rot": 0.0
    }
    next_uid += 1
    objects.append(obj)
    selected_uid = int(obj["uid"])
    selection_changed.emit(obj.duplicate(true))
    content_changed.emit()
    queue_redraw()
    grab_focus()

func add_avatar(label: String) -> void:
    var middle := to_world(size * 0.5)
    var color: String = str(["#CE6D3C", "#3C82B5", "#639F76", "#9B72BA", "#C59D40"][next_uid % 5])
    var obj := {
        "uid": next_uid, "type": "avatar", "name": label,
        "x": middle.x + (next_uid % 4) * 22.0,
        "y": middle.y + (next_uid % 3) * 23.0,
        "rot": 0.0, "color": color, "trail": []
    }
    next_uid += 1
    objects.append(obj)
    selected_uid = int(obj["uid"])
    selection_changed.emit(obj.duplicate(true))
    content_changed.emit()
    queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("EAE5DD"))
    draw_set_transform(view_origin, 0.0, Vector2(view_zoom, view_zoom))
    if source_texture != null:
        draw_texture_rect(source_texture, Rect2(Vector2.ZERO, SOURCE_SIZE), false)
    if grid_enabled:
        _draw_grid()
    if show_trails:
        _draw_trails()
    for obj in objects:
        _draw_object(obj)
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    # Ligne de mesure fidèle à la cote de 14,20 m de la page 5.
    var start := to_screen(Vector2(782, 248))
    var end := to_screen(Vector2(1144, 735))
    if grid_enabled:
        draw_line(start, end, Color(0.75, 0.36, 0.20, 0.5), 1.6, true)
    draw_rect(Rect2(Vector2(16, size.y - 37), Vector2(280, 26)), Color("FFFCF6E8"), true)
    draw_string(ThemeDB.fallback_font, Vector2(25, size.y - 19), "Plan source · page 5   |   14,20 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_INK)

func _draw_grid() -> void:
    var c := Color(0.13, 0.36, 0.42, 0.115)
    var step: float = PIXELS_PER_METER
    for i in range(0, 38):
        var x: float = i * step
        draw_line(Vector2(x, 76), Vector2(x, 1030), c, 0.8)
    for i in range(0, 25):
        var y: float = i * step
        draw_line(Vector2(42, y), Vector2(1517, y), c, 0.8)

func _draw_trails() -> void:
    for obj in objects:
        if str(obj.get("type")) != "avatar":
            continue
        var points: Array = obj.get("trail", [])
        if points.size() < 2:
            continue
        var c := Color(str(obj.get("color", "#CE6D3C")))
        c.a = 0.58
        for i in range(1, points.size()):
            var p1: Array = points[i-1]
            var p2: Array = points[i]
            draw_line(Vector2(float(p1[0]),float(p1[1])),Vector2(float(p2[0]),float(p2[1])),c,3.0,true)

func _get_size(obj: Dictionary) -> Vector2:
    if str(obj.get("type")) == "avatar":
        return Vector2(25, 25)
    var entry: Dictionary = catalog_by_id.get(str(obj.get("type")), {})
    return Vector2(float(entry.get("w", 48)), float(entry.get("h", 45)))

func _draw_object(obj: Dictionary) -> void:
    var center := Vector2(float(obj.get("x",0)), float(obj.get("y",0)))
    var rot := deg_to_rad(float(obj.get("rot", 0)))
    var dims := _get_size(obj)
    var type_id: String = str(obj.get("type", ""))
    draw_set_transform(to_screen(center), rot, Vector2(view_zoom, view_zoom))
    if type_id == "avatar":
        draw_circle(Vector2.ZERO, 14.0, Color(str(obj.get("color", "#CE6D3C"))))
        draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 30, Color.WHITE, 2.4, true)
        draw_circle(Vector2(0, -4), 4, Color.WHITE)
        draw_line(Vector2(0, 1),Vector2(0, 7),Color.WHITE,2.5,true)
        draw_string(ThemeDB.fallback_font, Vector2(19, 3), str(obj.get("name", "Agent")), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_INK)
        if str(obj.get("action","libre")) != "libre":
            draw_string(ThemeDB.fallback_font, Vector2(19, 20), str(obj.get("action","")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_ACCENT)
    else:
        var rect := Rect2(-dims*0.5, dims)
        draw_rect(rect.grow(3.0), Color("FFFFFFB8"))
        if textures.has(type_id):
            draw_texture_rect(textures[type_id], rect, false)
        else:
            draw_rect(rect, Color("9DB6BA"), true)
        draw_rect(rect, Color("63757B98"), false, 1.2)
    if int(obj.get("uid", -2)) == selected_uid:
        var outline := Rect2(-dims * 0.5, dims).grow(6.0)
        draw_rect(outline, COLOR_ACCENT, false, 2.5)
        draw_circle(Vector2(outline.end.x, outline.position.y), 4.0, COLOR_ACCENT)
    draw_set_transform(view_origin, 0.0, Vector2(view_zoom, view_zoom))

func _index_by_uid(uid: int) -> int:
    for i in objects.size():
        if int(objects[i].get("uid", -1)) == uid:
            return i
    return -1

func _hit_test(world_position: Vector2) -> int:
    for index in range(objects.size()-1, -1, -1):
        var obj: Dictionary = objects[index]
        var center := Vector2(float(obj.get("x",0)), float(obj.get("y",0)))
        var local: Vector2 = (world_position-center).rotated(-deg_to_rad(float(obj.get("rot", 0))))
        var dim: Vector2 = _get_size(obj)
        if Rect2(-dim * 0.5-Vector2(7,7),dim+Vector2(14,14)).has_point(local):
            return index
    return -1

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            zoom_at(event.position, 1.13)
            accept_event()
            return
        if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            zoom_at(event.position, 1.0/1.13)
            accept_event()
            return
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                grab_focus()
                var pos := to_world(event.position)
                var idx := _hit_test(pos)
                selected_uid = int(objects[idx].get("uid",-1)) if idx >= 0 else -1
                selection_changed.emit(objects[idx].duplicate(true) if idx >= 0 else {})
                if idx >= 0:
                    var clicked: Dictionary = objects[idx]
                    var is_avatar: bool = str(clicked.get("type", "")) == "avatar"
                    dragging = (not multiplayer_mode) or ((is_avatar and not room_paused and selected_uid == local_avatar_uid) or (not is_avatar and may_edit_equipment))
                    drag_anchor = Vector2(float(objects[idx].get("x")),float(objects[idx].get("y"))) - pos
                queue_redraw()
            else:
                if dragging:
                    dragging = false
                    var released_index := _index_by_uid(selected_uid)
                    if multiplayer_mode and released_index >= 0 and str(objects[released_index].get("type", "")) == "avatar":
                        avatar_motion.emit(float(objects[released_index]["x"]),float(objects[released_index]["y"]))
                    else:
                        content_changed.emit()
            accept_event()
            return
        if event.button_index in [MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
            panning = event.pressed
            mouse_anchor = event.position
            accept_event()
            return
    if event is InputEventMouseMotion:
        pointer_changed.emit(to_world(event.position))
        if panning:
            view_origin += event.position - mouse_anchor
            mouse_anchor = event.position
            queue_redraw()
            accept_event()
            return
        if dragging:
            var idx := _index_by_uid(selected_uid)
            if idx >= 0:
                var destination := to_world(event.position) + drag_anchor
                if Input.is_key_pressed(KEY_SHIFT):
                    destination = Vector2(roundf(destination.x/PIXELS_PER_METER)*PIXELS_PER_METER,roundf(destination.y/PIXELS_PER_METER)*PIXELS_PER_METER)
                destination.x = clampf(destination.x, 12.0, SOURCE_SIZE.x-12.0)
                destination.y = clampf(destination.y, 80.0, SOURCE_SIZE.y-10.0)
                var obj: Dictionary = objects[idx]
                if multiplayer_mode and str(obj.get("type")) == "avatar" and _avatar_collision(destination):
                    return
                if simulation_mode and str(obj.get("type")) == "avatar":
                    var trail: Array = obj.get("trail", [])
                    if trail.is_empty():
                        trail.append([float(obj["x"]),float(obj["y"])])
                    var last: Array = trail.back()
                    if Vector2(float(last[0]),float(last[1])).distance_to(destination)>8.0:
                        trail.append([destination.x,destination.y])
                    obj["trail"] = trail
                obj["x"] = destination.x
                obj["y"] = destination.y
                objects[idx] = obj
                selection_changed.emit(obj.duplicate(true))
                if multiplayer_mode and str(obj.get("type")) == "avatar":
                    motion_cooldown -= 0.025
                    if motion_cooldown <= 0.0:
                        motion_cooldown = 0.12
                        avatar_motion.emit(destination.x,destination.y)
                queue_redraw()
                accept_event()
                return
    if event is InputEventKey and event.pressed and not event.echo and not multiplayer_mode:
        if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
            delete_selection()
        elif event.keycode == KEY_R:
            rotate_selection(90.0)
        elif event.keycode == KEY_D:
            duplicate_selection()

func rotate_selection(degrees: float) -> void:
    var idx := _index_by_uid(selected_uid)
    if idx < 0 or (multiplayer_mode and (not may_edit_equipment or str(objects[idx].get("type")) == "avatar")):
        return
    var obj: Dictionary = objects[idx]
    obj["rot"] = fposmod(float(obj.get("rot",0.0)) + degrees,360.0)
    objects[idx] = obj
    selection_changed.emit(obj.duplicate(true))
    content_changed.emit()
    queue_redraw()

func delete_selection() -> void:
    var idx := _index_by_uid(selected_uid)
    if idx < 0 or (multiplayer_mode and (not may_edit_equipment or str(objects[idx].get("type")) == "avatar")):
        return
    objects.remove_at(idx)
    selected_uid = -1
    selection_changed.emit({})
    content_changed.emit()
    queue_redraw()

func duplicate_selection() -> void:
    var idx := _index_by_uid(selected_uid)
    if idx < 0 or (multiplayer_mode and (not may_edit_equipment or str(objects[idx].get("type")) == "avatar")):
        return
    var obj: Dictionary = objects[idx].duplicate(true)
    obj["uid"] = next_uid
    next_uid += 1
    obj["x"] = float(obj.get("x",0)) + 35.0
    obj["y"] = float(obj.get("y",0)) + 35.0
    if str(obj.get("type")) == "avatar":
        obj["trail"] = []
    objects.append(obj)
    selected_uid = int(obj["uid"])
    selection_changed.emit(obj.duplicate(true))
    content_changed.emit()
    queue_redraw()

func clear_trails() -> void:
    for i in objects.size():
        if str(objects[i].get("type")) == "avatar":
            objects[i]["trail"] = []
    content_changed.emit()
    queue_redraw()

func analyze() -> Dictionary:
    var overlaps: int = 0
    var travel_m: float = 0.0
    var count_equip: int = 0
    var count_avatar: int = 0
    for obj in objects:
        if str(obj.get("type")) == "avatar":
            count_avatar += 1
            var trail: Array = obj.get("trail", [])
            for i in range(1,trail.size()):
                travel_m += Vector2(float(trail[i-1][0]),float(trail[i-1][1])).distance_to(Vector2(float(trail[i][0]),float(trail[i][1]))) / PIXELS_PER_METER
        else:
            count_equip += 1
    for i in range(objects.size()):
        if str(objects[i].get("type")) == "avatar":
            continue
        var a: Dictionary = objects[i]
        var da := _get_size(a)
        var ra := Rect2(Vector2(float(a["x"]),float(a["y"])) - da*0.5, da)
        for j in range(i+1,objects.size()):
            var b: Dictionary = objects[j]
            if str(b.get("type")) == "avatar":
                continue
            var db := _get_size(b)
            var rb := Rect2(Vector2(float(b["x"]),float(b["y"])) - db*0.5, db)
            if ra.intersects(rb):
                overlaps += 1
    return {"equipments":count_equip,"avatars":count_avatar,"overlaps":overlaps,"distance_m":travel_m}
