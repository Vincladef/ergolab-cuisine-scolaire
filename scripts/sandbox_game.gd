extends Node2D
## ErgoLab, bac à sable 2D natif Godot 4.4.
## La maquette est issue du plan de travail de la page 5 du TP.
## Les limites géométriques tracées sont une approximation révisable du plan image.

const RoomNetwork = preload("res://scripts/network_room.gd")
const MAP := preload("res://assets/plan_original.png")
const SCALE_PX_PER_M := 42.82
const INK := Color("#18323B")
const MUTED := Color("#647B7E")
const PAPER := Color("#FFFDF7")
const DARK := Color("#19383F")
const GREEN := Color("#416F63")
const ORANGE := Color("#C16D3F")
const AVATAR_COLORS := ["#CE6D3C", "#3C82B5", "#639F76", "#9B72BA", "#C59D40", "#D06E89", "#3B968D", "#8A7B63"]
const ACTIONS := ["libre", "préparer", "cuisiner", "porter", "pousser", "plonge", "servir", "attendre", "nettoyer", "livrer"]
const CATALOG := [
    {"id":"chariot","label":"Chariot","w":29.0,"h":17.0,"kind":"Transport"},
    {"id":"table","label":"Plan de travail","w":28.0,"h":83.0,"kind":"Préparation"},
    {"id":"evier","label":"Évier","w":31.0,"h":85.0,"kind":"Préparation"},
    {"id":"frigo","label":"Réfrigérateur","w":35.0,"h":85.0,"kind":"Stockage"},
    {"id":"etagere","label":"Étagère","w":34.0,"h":106.0,"kind":"Stockage"},
    {"id":"plonge","label":"Plonge","w":31.0,"h":181.0,"kind":"Entretien"},
    {"id":"cuisson","label":"Table de cuisson","w":41.0,"h":27.0,"kind":"Cuisson"},
    {"id":"sauteuse","label":"Sauteuse","w":41.0,"h":43.0,"kind":"Cuisson"},
    {"id":"marmite","label":"Marmite","w":41.0,"h":34.0,"kind":"Cuisson"},
    {"id":"four","label":"Four","w":43.0,"h":53.0,"kind":"Cuisson"},
    {"id":"friteuse","label":"Friteuse","w":41.0,"h":37.0,"kind":"Cuisson"},
    {"id":"meuble_chaud","label":"Meuble chaud","w":32.0,"h":74.0,"kind":"Cuisson"},
    {"id":"eplucheuse","label":"Éplucheuse","w":35.0,"h":37.0,"kind":"Préparation"},
    {"id":"lave_mains","label":"Lave-mains","w":22.0,"h":46.0,"kind":"Entretien"}
]
## Repère simplifié des parois de la pièce principale, déduit visuellement de la p.5.
var walk_poly: PackedVector2Array = PackedVector2Array([
    Vector2(648,342),Vector2(956,113),Vector2(1213,460),
    Vector2(1183,480),Vector2(1231,548),Vector2(1059,767),
    Vector2(933,600),Vector2(910,610),Vector2(902,589),
    Vector2(755,373),Vector2(641,462),Vector2(610,421)
])

var network: Node
var camera: Camera2D
var hud: CanvasLayer
var ui_root: Control
var name_input: LineEdit
var room_input: LineEdit
var nickname: String = "Agent"
var color_index: int = 0
var color_button: Button
var connect_status: Label
var mini_status: Label
var scenario_picker: OptionButton
var pause_button: Button
var lock_button: Button
var role_label: Label
var people_label: Label
var action_menu: OptionButton
var scenario_title: LineEdit
var obs_line: LineEdit
var show_grid: bool = true
var show_paths: bool = true
var room_open: bool = false
var participants: Array = []
var selected_uid: int = -1
var dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var waypoint: Vector2 = Vector2.ZERO
var has_waypoint: bool = false
var local_avatar: Dictionary = {"x":981.0,"y":439.0,"action":"libre","name":"Moi","color":"#CE6D3C","trail":[]}
var own_id: String = ""
var room_revision: int = 1
var active_index: int = 0
var paused: bool = false
var locked: bool = false
var scenes: Array = []
var equipment_textures: Dictionary = {}
var equipment_sizes: Dictionary = {}
var equipment_labels: Dictionary = {}
var move_elapsed: float = 0.0
var status_elapsed: float = 0.0
var view_scale: float = 1.0
var zoom_override: float = 1.0
var is_loading: bool = false
var last_world_mouse: Vector2 = Vector2.ZERO
var local_distance: float = 0.0
var action_started: int = 0

func _ready() -> void:
    RenderingServer.set_default_clear_color(Color("#E6E7DF"))
    get_window().title = "ErgoLab · Bac à sable Godot"
    for kind in CATALOG:
        var id: String = kind["id"]
        equipment_sizes[id] = Vector2(float(kind["w"]),float(kind["h"]))
        equipment_labels[id] = kind["label"]
        var tex_path: String = "res://assets/equipment/%s.png" % id
        if ResourceLoader.exists(tex_path):
            equipment_textures[id] = load(tex_path)
    scenes = [{"name":"Aménagement A","notes":"","objects":[]},{"name":"Aménagement B","notes":"","objects":[]}]
    camera = Camera2D.new()
    camera.name = "CameraJeu"
    add_child(camera)
    camera.make_current()
    network = RoomNetwork.new()
    add_child(network)
    network.session_ready.connect(_on_room_ready)
    network.state_received.connect(_on_room_state)
    network.message_received.connect(_on_room_packet)
    network.connection_status.connect(_status)
    _load_local_scenes()
    _build_ui()
    get_viewport().size_changed.connect(_resize)
    call_deferred("_resize")
    var room_code: String = network.room_from_url()
    var saved: Dictionary = network._read_identity()
    var known: Dictionary = saved.get("rooms",{})
    if not room_code.is_empty():
        room_input.text = room_code
        if known.has(room_code):
            network.enter_room(room_code,name_input.text,AVATAR_COLORS[color_index])
        else:
            _status("Invitation reçue. Entre ton pseudonyme, puis rejoins la salle.")
    elif not known.is_empty():
        var previous: String = str(known.keys()[0])
        room_input.text = previous
        network.enter_room(previous,name_input.text,AVATAR_COLORS[color_index])
    else:
        _status("Bac à sable prêt. Déplace ton avatar avec les flèches ou ZQSD, ou clique dans le plan.")
    set_process(true)

func _panel(fill: Color = PAPER) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = Color("#D6DCD3")
    style.set_border_width_all(1)
    style.set_corner_radius_all(12)
    style.content_margin_left = 12.0
    style.content_margin_right = 12.0
    style.content_margin_top = 10.0
    style.content_margin_bottom = 10.0
    return style

func _label(text: String, font: int = 13, tint: Color = INK) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_color_override("font_color",tint)
    l.add_theme_font_size_override("font_size",font)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return l

func _button(text: String, callback: Callable, accent: bool = false) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size.y = 35
    b.add_theme_font_size_override("font_size",12)
    b.add_theme_color_override("font_color",Color.WHITE if accent else INK)
    b.add_theme_stylebox_override("normal",_panel(ORANGE if accent else PAPER))
    b.add_theme_stylebox_override("hover",_panel(Color("#A95330") if accent else Color("#EEECE3")))
    b.pressed.connect(callback)
    return b

func _space(h: float) -> Control:
    var c := Control.new()
    c.custom_minimum_size.y = h
    return c

func _build_ui() -> void:
    hud = CanvasLayer.new()
    hud.name = "InterfaceJeu"
    add_child(hud)
    ui_root = Control.new()
    ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hud.add_child(ui_root)

    var top := PanelContainer.new()
    top.name = "BarrePrincipale"
    top.add_theme_stylebox_override("panel",_panel(PAPER))
    top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    top.offset_bottom = 72
    ui_root.add_child(top)
    var head := HBoxContainer.new()
    head.add_theme_constant_override("separation",9)
    top.add_child(head)
    var title := _label("ERGOLAB  •  CUISINE SCOLAIRE",17,INK)
    title.custom_minimum_size.x = 305
    title.autowrap_mode = TextServer.AUTOWRAP_OFF
    head.add_child(title)
    name_input = LineEdit.new()
    name_input.placeholder_text = "Ton pseudonyme"
    name_input.text = "Participant"
    name_input.custom_minimum_size = Vector2(140,38)
    name_input.add_theme_color_override("font_color",INK)
    name_input.add_theme_stylebox_override("normal",_panel(PAPER))
    head.add_child(name_input)
    color_button = _button("● Couleur",_cycle_color)
    color_button.custom_minimum_size.x = 86
    head.add_child(color_button)
    head.add_child(_button("Créer une salle",_new_room,true))
    room_input = LineEdit.new()
    room_input.placeholder_text = "Code de salle"
    room_input.custom_minimum_size = Vector2(135,38)
    room_input.add_theme_color_override("font_color",INK)
    room_input.add_theme_stylebox_override("normal",_panel(PAPER))
    head.add_child(room_input)
    head.add_child(_button("Rejoindre",_join_room))
    head.add_child(_button("Lien",_copy_link))
    var grow := Control.new()
    grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(grow)
    role_label = _label("LOCAL",12,GREEN)
    role_label.custom_minimum_size.x = 115
    role_label.autowrap_mode = TextServer.AUTOWRAP_OFF
    role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    head.add_child(role_label)

    var left := PanelContainer.new()
    left.name = "PaletteEquipements"
    left.add_theme_stylebox_override("panel",_panel(PAPER))
    left.position = Vector2(10,84)
    left.size = Vector2(211,690)
    ui_root.add_child(left)
    var ls := ScrollContainer.new()
    ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left.add_child(ls)
    var palette := VBoxContainer.new()
    palette.custom_minimum_size.x = 183
    palette.add_theme_constant_override("separation",5)
    ls.add_child(palette)
    palette.add_child(_label("MATÉRIEL À PLACER",14,ORANGE))
    palette.add_child(_label("Objets du dossier, page 6",11,MUTED))
    palette.add_child(_space(8))
    var group: String = ""
    for entry in CATALOG:
        var typ: String = str(entry["kind"])
        if group != typ:
            group = typ
            palette.add_child(_space(6))
            palette.add_child(_label(group.to_upper(),10,MUTED))
        var eq_id: String = str(entry["id"])
        palette.add_child(_button("+  " + str(entry["label"]),func(): _spawn_equipment(eq_id)))
    palette.add_child(_space(10))
    palette.add_child(_label("SOURIS",10,MUTED))
    palette.add_child(_label("Clic au sol : avancer\nGlisser : placer le mobilier\nMolette : zoomer",11,MUTED))

    var right := PanelContainer.new()
    right.name = "AtelierJeu"
    right.add_theme_stylebox_override("panel",_panel(PAPER))
    ui_root.add_child(right)
    right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
    right.position = Vector2(-251,84)
    right.size = Vector2(241,690)
    var rs := ScrollContainer.new()
    rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    right.add_child(rs)
    var actions := VBoxContainer.new()
    actions.custom_minimum_size.x = 212
    actions.add_theme_constant_override("separation",8)
    rs.add_child(actions)
    actions.add_child(_label("BAC À SABLE",15,ORANGE))
    actions.add_child(_label("Déplace-toi. Essaie des tâches. Observe les trajets.",12,MUTED))
    action_menu = OptionButton.new()
    for index in ACTIONS.size():
        action_menu.add_item(str(ACTIONS[index]).capitalize(),index)
    actions.add_child(action_menu)
    actions.add_child(_button("AGIR  ·  E",_perform_action,true))
    actions.add_child(_button("Arrêter l'action",func(): _set_action("libre",-1)))
    actions.add_child(_space(4))
    actions.add_child(_label("SCÉNARIO",12,ORANGE))
    scenario_picker = OptionButton.new()
    scenario_picker.item_selected.connect(_select_scenario)
    actions.add_child(scenario_picker)
    scenario_title = LineEdit.new()
    scenario_title.placeholder_text = "Nom de l'aménagement"
    scenario_title.add_theme_color_override("font_color",INK)
    scenario_title.add_theme_stylebox_override("normal",_panel(PAPER))
    scenario_title.text_submitted.connect(func(_v): _rename_scenario())
    actions.add_child(scenario_title)
    actions.add_child(_button("Renommer",_rename_scenario))
    actions.add_child(_button("Dupliquer",_duplicate_scenario))
    actions.add_child(_button("Tourner le meuble  ·  R",_rotate_selection))
    actions.add_child(_button("Retirer le meuble  ·  Suppr",_remove_selection))
    actions.add_child(_space(4))
    actions.add_child(_label("ANIMATION",12,ORANGE))
    pause_button = _button("Mettre en pause",_toggle_pause)
    actions.add_child(pause_button)
    lock_button = _button("Verrouiller les meubles",_toggle_lock)
    actions.add_child(lock_button)
    actions.add_child(_button("Réinitialiser la vue",_reset_camera))
    actions.add_child(_button("Afficher / cacher grille",func(): show_grid = not show_grid; queue_redraw()))
    actions.add_child(_button("Afficher / cacher trajets",func(): show_paths = not show_paths; queue_redraw()))
    actions.add_child(_space(4))
    actions.add_child(_label("OBSERVATION ERGONOMIQUE",12,ORANGE))
    obs_line = LineEdit.new()
    obs_line.placeholder_text = "Ex. Passage encombré"
    actions.add_child(obs_line)
    actions.add_child(_button("Noter (observation)",_add_observation))
    people_label = _label("1 avatar local",11,MUTED)
    actions.add_child(people_label)

    var bottom := PanelContainer.new()
    bottom.add_theme_stylebox_override("panel",_panel(DARK))
    bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    bottom.offset_top = -45
    ui_root.add_child(bottom)
    var bottom_bar := HBoxContainer.new()
    bottom.add_child(bottom_bar)
    connect_status = _label("",12,Color.WHITE)
    connect_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bottom_bar.add_child(connect_status)
    mini_status = _label("",12,Color("#E8CFB4"))
    mini_status.custom_minimum_size.x = 290
    mini_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    bottom_bar.add_child(mini_status)
    _refresh_scenarios()

func _resize() -> void:
    if camera == null or ui_root == null:
        return
    var s: Vector2 = get_viewport_rect().size
    ui_root.size = s
    var left: Control = ui_root.get_node("PaletteEquipements")
    var right: Control = ui_root.get_node("AtelierJeu")
    left.position = Vector2(10,84)
    left.size = Vector2(211,maxf(300,s.y-141))
    right.position = Vector2(s.x-251,84)
    right.size = Vector2(241,maxf(300,s.y-141))
    var field_w := maxf(260,s.x-211-241-36)
    var field_h := maxf(220,s.y-72-45-30)
    view_scale = minf(field_w/840.0, field_h/800.0)
    camera.zoom = Vector2.ONE*clampf(view_scale*zoom_override,0.28,2.8)
    var canvas_offset_x := ((211.0-241.0)*0.5)/camera.zoom.x
    camera.position = Vector2(957.0 - canvas_offset_x, 445.0)
    queue_redraw()

func _reset_camera() -> void:
    zoom_override = 1.0
    _resize()

func _cycle_color() -> void:
    color_index = (color_index+1)%AVATAR_COLORS.size()
    color_button.text = "● Couleur " + str(color_index+1)
    if not network.has_room():
        local_avatar["color"] = AVATAR_COLORS[color_index]
        queue_redraw()

func _new_room() -> void:
    nickname = name_input.text.strip_edges()
    network.start_new(nickname,AVATAR_COLORS[color_index])

func _join_room() -> void:
    nickname = name_input.text.strip_edges()
    var code := room_input.text.strip_edges().to_lower()
    if code.is_empty():
        _status("Indique d'abord le code de la salle.")
        return
    network.enter_room(code,nickname,AVATAR_COLORS[color_index])

func _copy_link() -> void:
    network.copy_link()
    _status("Lien de salle copié." if network.has_room() else "Crée ou rejoins une salle.")

func _status(msg: String) -> void:
    if connect_status != null:
        connect_status.text = msg

func _active() -> Dictionary:
    return scenes[clampi(active_index,0,scenes.size()-1)]

func _objects() -> Array:
    return _active().get("objects",[])

func _my_avatar() -> Dictionary:
    if not network.has_room():
        return local_avatar
    for p in participants:
        if str(p.get("id","")) == network.peer_id:
            return p.get("avatar",local_avatar)
    return local_avatar

func _my_pos() -> Vector2:
    var a: Dictionary = _my_avatar()
    return Vector2(float(a.get("x",981)),float(a.get("y",439)))

func _me_update(p: Vector2) -> void:
    var avatar: Dictionary = _my_avatar().duplicate(true)
    var old := Vector2(float(avatar.get("x",981)),float(avatar.get("y",439)))
    avatar["x"] = p.x
    avatar["y"] = p.y
    var trail: Array = avatar.get("trail",[])
    if trail.is_empty() or p.distance_to(Vector2(float(trail.back()[0]),float(trail.back()[1])))>13.0:
        trail.append([p.x,p.y])
    if trail.size()>220:
        trail.remove_at(0)
    avatar["trail"] = trail
    local_distance += old.distance_to(p)/SCALE_PX_PER_M
    if network.has_room():
        for i in participants.size():
            if str(participants[i].get("id",""))==network.peer_id:
                participants[i]["avatar"] = avatar
                break
    local_avatar = avatar

func _my_color() -> Color:
    if network.has_room():
        for p in participants:
            if str(p.get("id",""))==network.peer_id:
                return Color(str(p.get("color",AVATAR_COLORS[0])))
    return Color(str(local_avatar.get("color",AVATAR_COLORS[color_index])))

func _inside_kitchen(p: Vector2) -> bool:
    return Geometry2D.is_point_in_polygon(p,walk_poly)

func _collision(p: Vector2) -> bool:
    if not _inside_kitchen(p):
        return true
    for obj in _objects():
        var center := Vector2(float(obj.get("x",0)),float(obj.get("y",0)))
        var dims: Vector2 = equipment_sizes.get(str(obj.get("type","")),Vector2(40,50))
        var relative: Vector2 = (p-center).rotated(-deg_to_rad(float(obj.get("rot",0))))
        if absf(relative.x)<dims.x*0.5+13.0 and absf(relative.y)<dims.y*0.5+13.0:
            return true
    for p2 in participants:
        if str(p2.get("id",""))==network.peer_id or not bool(p2.get("connected",true)):
            continue
        var v: Dictionary = p2.get("avatar",{})
        if p.distance_to(Vector2(float(v.get("x",0)),float(v.get("y",0))))<27.0:
            return true
    return false

func _process(delta: float) -> void:
    if ui_root == null:
        return
    var focused: Control = get_viewport().gui_get_focus_owner()
    var typing: bool = focused is LineEdit or focused is TextEdit
    var a: Dictionary = _my_avatar()
    var speed := 135.0
    if str(a.get("action","libre"))=="porter": speed=88.0
    if str(a.get("action","libre"))=="pousser": speed=72.0
    var direction := Vector2.ZERO
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):direction.x-=1
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):direction.x+=1
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_UP):direction.y-=1
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):direction.y+=1
    if typing:
        direction=Vector2.ZERO
        has_waypoint=false
    if not direction.is_zero_approx():
        has_waypoint=false
        direction=direction.normalized()
    elif has_waypoint:
        var distance := _my_pos().distance_to(waypoint)
        if distance<8.0:
            has_waypoint=false
        else:
            direction=(_my_pos().direction_to(waypoint))
    if not direction.is_zero_approx() and not paused and (not network.has_room() or network.connected):
        var origin := _my_pos()
        var target := origin+direction*speed*delta
        if not _collision(target):
            _me_update(target)
            move_elapsed+=delta
            if network.has_room() and move_elapsed>0.17:
                move_elapsed=0.0
                network.send_move(target.x,target.y)
        else:
            has_waypoint=false
    status_elapsed+=delta
    if status_elapsed>=0.25:
        status_elapsed=0.0
        if mini_status:
            var eq := _nearest_equipment(145.0)
            mini_status.text = "%d agent(s)  ·  %.1f m parcourus%s" % [maxi(1,participants.size()),local_distance,"  ·  poste proche" if eq>=0 else ""]
    queue_redraw()

func _nearest_equipment(radius: float) -> int:
    var found := -1
    var best := radius
    for obj in _objects():
        var distance := _my_pos().distance_to(Vector2(float(obj.get("x",0)),float(obj.get("y",0))))
        if distance < best:
            best=distance
            found=int(obj.get("uid",-1))
    return found

func _action_target(action: String) -> int:
    if action in ["libre","attendre","livrer"]:return -1
    var candidates: Array=[]
    match action:
        "préparer":candidates=["table","evier","eplucheuse","frigo"]
        "cuisiner":candidates=["cuisson","marmite","sauteuse","four","friteuse"]
        "porter":candidates=["chariot","table","frigo","meuble_chaud"]
        "pousser":candidates=["chariot"]
        "plonge":candidates=["plonge","evier"]
        "servir":candidates=["table","meuble_chaud","chariot"]
        "nettoyer":candidates=["plonge","evier","table"]
    var best: float=140.0
    var result: int=-1
    for o in _objects():
        if str(o.get("type","")) not in candidates:continue
        var d: float=_my_pos().distance_to(Vector2(float(o.get("x",0)),float(o.get("y",0))))
        if d<best:
            best=d
            result=int(o.get("uid",-1))
    return result

func _set_action(action: String,target: int) -> void:
    if paused:
        _status("Simulation en pause")
        return
    if network.has_room():
        network.send_interaction(action,target)
    else:
        local_avatar["action"]=action
        local_avatar["target"]=target
        _status("Action : "+action)
    queue_redraw()

func _perform_action() -> void:
    var action: String = ACTIONS[action_menu.selected]
    var nearest := _action_target(action)
    if nearest<0 and action not in ["libre","attendre","livrer"]:
        _status("Approche-toi d'un poste avant d'effectuer cette action.")
        return
    _set_action(action,nearest)

func _spawn_equipment(kind: String) -> void:
    if locked and network.has_room() and network.role!="host":
        _status("Le mobilier est verrouillé par l'animateur")
        return
    if not equipment_sizes.has(kind):return
    var pos:=_my_pos()+Vector2(62,12)
    if not _inside_kitchen(pos):pos=Vector2(980,430)
    var used: int = 0
    for obj in _objects():used=maxi(used,int(obj.get("uid",0)))
    var obj: Dictionary={"uid":used+1,"type":kind,"x":pos.x,"y":pos.y,"rot":0.0}
    _objects().append(obj)
    selected_uid=int(obj["uid"])
    _save_layout()
    _status("Ajout : "+str(equipment_labels.get(kind,kind)))

func _item_at(p: Vector2) -> int:
    var objects: Array = _objects()
    for i in range(objects.size()-1,-1,-1):
        var o: Dictionary=objects[i]
        var dims: Vector2=equipment_sizes.get(str(o.get("type","")),Vector2(34,40))
        var diff: Vector2=(p-Vector2(float(o.get("x",0)),float(o.get("y",0)))).rotated(-deg_to_rad(float(o.get("rot",0))))
        if absf(diff.x) <= dims.x*0.5+9 and absf(diff.y)<=dims.y*0.5+9:
            return i
    return -1

func _save_layout() -> void:
    if not network.has_room():
        _save_local_scenes()
    if network.has_room():
        network.send_layout(scenes,active_index,room_revision)
    queue_redraw()

func _rotate_selection() -> void:
    for i in _objects().size():
        if int(_objects()[i].get("uid",-1))==selected_uid:
            _objects()[i]["rot"]=fposmod(float(_objects()[i].get("rot",0))+90.0,360.0)
            _save_layout()
            return

func _remove_selection() -> void:
    for i in _objects().size():
        if int(_objects()[i].get("uid",-1))==selected_uid:
            _objects().remove_at(i)
            selected_uid=-1
            _save_layout()
            return

func _refresh_scenarios() -> void:
    if scenario_picker==null:return
    is_loading=true
    scenario_picker.clear()
    for i in scenes.size():
        scenario_picker.add_item(str(scenes[i].get("name","Scénario")),i)
    scenario_picker.select(active_index)
    if scenario_title:scenario_title.text=str(_active().get("name","Aménagement"))
    is_loading=false

func _select_scenario(idx: int) -> void:
    if is_loading:return
    active_index=idx
    selected_uid=-1
    _refresh_scenarios()
    _save_layout()

func _rename_scenario() -> void:
    var value := scenario_title.text.strip_edges().substr(0,70)
    if value.is_empty():return
    scenes[active_index]["name"]=value
    _refresh_scenarios()
    _save_layout()

func _duplicate_scenario() -> void:
    if scenes.size()>=12:
        _status("Limite de 12 aménagements")
        return
    var copy: Dictionary=_active().duplicate(true)
    copy["name"]="Aménagement " + str(scenes.size()+1)
    scenes.append(copy)
    active_index=scenes.size()-1
    selected_uid=-1
    _refresh_scenarios()
    _save_layout()

func _toggle_pause() -> void:
    if network.has_room():
        if network.role!="host":return
        network.send_pause(not paused)
    else:
        paused=not paused
        pause_button.text="Reprendre" if paused else "Mettre en pause"

func _toggle_lock() -> void:
    if network.has_room():
        if network.role!="host":return
        network.send_lock(not locked)
    else:
        locked=not locked
    lock_button.text="Déverrouiller les meubles" if locked else "Verrouiller les meubles"

func _add_observation() -> void:
    var txt:=obs_line.text.strip_edges()
    if txt.is_empty():return
    _status("Observation : "+txt)
    if network.has_room():
        # Le module d'atelier reçoit la remarque enregistrée via une API authentifiée.
        _post_observation(txt)
    obs_line.clear()

func _post_observation(txt: String) -> void:
    var req:=HTTPRequest.new()
    add_child(req)
    req.request_completed.connect(func(_result:int,code:int,_headers:PackedStringArray,_data:PackedByteArray):
        if code!=200:_status("Observation non sauvegardée (HTTP " + str(code) + ")")
        req.queue_free())
    var body: Dictionary={"action":"observation","room":network.room,"id":network.peer_id,"token":network.token,"category":"circulation","severity":2,"comment":txt,"scenario_index":active_index}
    req.request(network.server_origin+"/api/workshop",PackedStringArray(["Content-Type: application/json"]),HTTPClient.METHOD_POST,JSON.stringify(body))

func _draw() -> void:
    draw_rect(Rect2(-300,-300,2400,1700),Color("#E8E7E1"))
    draw_texture_rect(MAP,Rect2(0,0,1571,1088),false,Color(1,1,1,0.9))
    draw_colored_polygon(walk_poly,Color(0.79,0.91,0.82,0.22))
    draw_polyline(walk_poly,Color(0.22,0.50,0.40,0.75),3.2,true)
    draw_line(walk_poly[walk_poly.size()-1],walk_poly[0],Color(0.22,0.50,0.40,0.75),3.2,true)
    if show_grid:
        for x in range(0,39):
            draw_line(Vector2(float(x)*SCALE_PX_PER_M,50),Vector2(float(x)*SCALE_PX_PER_M,1050),Color(0.14,0.34,0.35,0.075),1.0)
        for y in range(0,28):
            draw_line(Vector2(45,float(y)*SCALE_PX_PER_M),Vector2(1490,float(y)*SCALE_PX_PER_M),Color(0.14,0.34,0.35,0.075),1.0)
    for o in _objects():_draw_equipment(o)
    if network.has_room():
        for person in participants:
            _draw_avatar(person)
    else:
        _draw_avatar({"id":"local","nickname":nickname if nickname!="" else "Moi","color":local_avatar.get("color",AVATAR_COLORS[color_index]),"avatar":local_avatar,"connected":true})
    if has_waypoint:
        draw_arc(waypoint,10,0,TAU,22,Color("#315E68"),2.0,true)
    # Indique sans ambiguïté le caractère approximatif des parois déduites de l'image.
    draw_string(ThemeDB.fallback_font,Vector2(775,80),"Contours de circulation à vérifier sur plan coté",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("#B06939"))

func _draw_equipment(o: Dictionary) -> void:
    var id: String=str(o.get("type",""))
    var size2: Vector2=equipment_sizes.get(id,Vector2(35,40))
    var pos:=Vector2(float(o.get("x",0)),float(o.get("y",0)))
    var angle:=deg_to_rad(float(o.get("rot",0)))
    draw_set_transform(pos,angle)
    var rect:=Rect2(-size2*0.5,size2)
    draw_rect(rect.grow(5),Color(1,1,1,0.89))
    if equipment_textures.has(id):
        draw_texture_rect(equipment_textures[id],rect,false)
    else:
        draw_rect(rect,Color("#B5C9CA"))
    draw_rect(rect,Color("#687E80"),false,1.8)
    if int(o.get("uid",-1))==selected_uid:
        draw_rect(rect.grow(8),ORANGE,false,3.5)
    draw_set_transform(Vector2.ZERO)

func _draw_avatar(person: Dictionary) -> void:
    var av: Dictionary=person.get("avatar",{})
    var pos:=Vector2(float(av.get("x",981)),float(av.get("y",439)))
    var color:=Color(str(person.get("color",AVATAR_COLORS[0])))
    var name: String=str(person.get("nickname","Agent"))
    if show_paths:
        var trail: Array=av.get("trail",[])
        for j in range(1,trail.size()):
            var a1: Array=trail[j-1]
            var a2: Array=trail[j]
            draw_line(Vector2(float(a1[0]),float(a1[1])),Vector2(float(a2[0]),float(a2[1])),Color(color.r,color.g,color.b,0.43),2.7,true)
    var bob: float=sin(float(Time.get_ticks_msec())*0.014)*1.7 if str(av.get("action","libre"))!="attendre" else 0.0
    draw_circle(pos+Vector2(0,6),17,Color(0,0,0,0.17))
    draw_circle(pos+Vector2(0,bob),14,color)
    draw_arc(pos+Vector2(0,bob),14.0,0,TAU,30,Color.WHITE,2.7,true)
    draw_circle(pos+Vector2(0,-5+bob),5,Color.WHITE)
    draw_line(pos+Vector2(0,2+bob),pos+Vector2(0,9+bob),Color.WHITE,3.0,true)
    var doing: String=str(av.get("action","libre"))
    # L'action de l'agent se lit aussi dans le jeu, sans menus supplémentaires.
    if doing=="porter" or doing=="livrer":
        draw_rect(Rect2(pos+Vector2(-11,-29+bob),Vector2(22,12)),Color("#CB9154"))
        draw_line(pos+Vector2(-9,-21+bob),pos+Vector2(9,-21+bob),Color("#704E39"),2)
    elif doing=="cuisiner":
        draw_circle(pos+Vector2(-15,-19+bob),5,Color("#F1A442"))
        draw_circle(pos+Vector2(-12,-23+bob),3,Color("#E36B3D"))
    elif doing=="plonge" or doing=="nettoyer":
        draw_arc(pos+Vector2(17,-18+bob),7,0,TAU,16,Color("#53ABD0"),2,true)
        draw_arc(pos+Vector2(21,-29+bob),4,0,TAU,12,Color("#53ABD0"),2,true)
    elif doing=="pousser":
        draw_line(pos+Vector2(8,-5+bob),pos+Vector2(24,-8+bob),Color.WHITE,3,true)
    var is_mine: bool = (str(person.get("id","")) == network.peer_id) if network.has_room() else true
    if is_mine:
        draw_arc(pos,21,0,TAU,30,ORANGE,2.3,true)
    draw_string(ThemeDB.fallback_font,pos+Vector2(19,-4),name,HORIZONTAL_ALIGNMENT_LEFT,-1,15,INK)
    if doing!="libre":
        draw_string(ThemeDB.fallback_font,pos+Vector2(19,12),doing,HORIZONTAL_ALIGNMENT_LEFT,-1,12,ORANGE)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
            get_viewport().gui_release_focus()
        if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed:
            zoom_override=clampf(zoom_override*1.12,0.56,3.0)
            _resize()
            get_viewport().set_input_as_handled()
        elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            zoom_override=clampf(zoom_override/1.12,0.56,3.0)
            _resize()
            get_viewport().set_input_as_handled()
        elif event.button_index==MOUSE_BUTTON_LEFT:
            if event.pressed:
                var wp:=get_global_mouse_position()
                var index:=_item_at(wp)
                if index>=0 and not locked:
                    selected_uid=int(_objects()[index].get("uid",-1))
                    dragging=true
                    drag_offset=Vector2(float(_objects()[index].get("x",0)),float(_objects()[index].get("y",0)))-wp
                    has_waypoint=false
                elif _inside_kitchen(wp):
                    waypoint=wp
                    has_waypoint=true
                    selected_uid=-1
                else:
                    selected_uid=-1
            else:
                if dragging:
                    dragging=false
                    _save_layout()
            queue_redraw()
            get_viewport().set_input_as_handled()
    elif event is InputEventMouseMotion:
        if dragging:
            var mousepos:=get_global_mouse_position()+drag_offset
            if _inside_kitchen(mousepos):
                for obj in _objects():
                    if int(obj.get("uid",-1))==selected_uid:
                        obj["x"]=mousepos.x
                        obj["y"]=mousepos.y
                        break
            queue_redraw()
            get_viewport().set_input_as_handled()
    elif event is InputEventKey and event.pressed and not event.echo:
        if event.keycode==KEY_E:_perform_action()
        elif event.keycode==KEY_R:_rotate_selection()
        elif event.keycode==KEY_DELETE:_remove_selection()

func _on_room_ready(data: Dictionary) -> void:
    role_label.text="ANIMATEUR" if network.role=="host" else "PARTICIPANT"
    room_input.text=network.room
    room_open=true
    var state: Variant=data.get("snapshot",{})
    if state is Dictionary:_on_room_state(state)
    _status("Salle " + network.room + " : partage le lien pour inviter le groupe")

func _on_room_state(state: Dictionary) -> void:
    if not (state.get("scenarios",[]) is Array):return
    scenes=state.get("scenarios",[]).duplicate(true)
    if scenes.is_empty():return
    active_index=clampi(int(state.get("active_index",0)),0,scenes.size()-1)
    room_revision=int(state.get("revision",1))
    paused=bool(state.get("paused",false))
    locked=bool(state.get("locked",false))
    participants=state.get("participants",[]).duplicate(true)
    pause_button.disabled=(network.role!="host")
    lock_button.disabled=(network.role!="host")
    pause_button.text="Reprendre" if paused else "Mettre en pause"
    lock_button.text="Déverrouiller les meubles" if locked else "Verrouiller les meubles"
    _refresh_scenarios()
    _refresh_people()
    queue_redraw()

func _refresh_people() -> void:
    var names: Array=[]
    for p in participants:
        names.append(str(p.get("nickname","Agent")))
    people_label.text="AGENTS CONNECTÉS : " + str(participants.size()) + "\n" + ", ".join(names)

func _on_room_packet(packet: Dictionary) -> void:
    var kind: String=str(packet.get("kind",""))
    var payload: Dictionary=packet.get("payload",{})
    match kind:
        "layout":
            var state: Dictionary={"scenarios":payload.get("scenarios",scenes),"active_index":payload.get("active_index",active_index),"revision":payload.get("revision",room_revision),"paused":paused,"locked":locked,"participants":participants}
            _on_room_state(state)
        "move":
            var id:String=str(payload.get("id",""))
            for i in participants.size():
                if str(participants[i].get("id",""))==id:
                    var av:Dictionary=participants[i].get("avatar",{})
                    av["x"]=payload.get("x",av.get("x",981))
                    av["y"]=payload.get("y",av.get("y",439))
                    av["trail"]=payload.get("trail",av.get("trail",[]))
                    participants[i]["avatar"]=av
                    break
            var pushed:Variant=payload.get("pushed",null)
            if pushed is Dictionary:
                room_revision=maxi(room_revision,int(pushed.get("revision",room_revision)))
                for obj in _objects():
                    if int(obj.get("uid",-1))==int(pushed.get("uid",-2)):
                        obj["x"]=pushed.get("x",obj.get("x",0))
                        obj["y"]=pushed.get("y",obj.get("y",0))
        "presence":
            var current:Variant=payload.get("participant",null)
            if current is Dictionary:
                var updated:=false
                for i in participants.size():
                    if str(participants[i].get("id",""))==str(current.get("id","")):
                        participants[i]=current
                        updated=true
                        break
                if not updated:participants.append(current)
            else:
                for i in participants.size():
                    if str(participants[i].get("id",""))==str(payload.get("id","")):
                        participants[i]["connected"]=bool(payload.get("connected",false))
            _refresh_people()
        "interaction":
            for i in participants.size():
                if str(participants[i].get("id",""))==str(payload.get("id","")):
                    participants[i]["avatar"]["action"]=str(payload.get("action","libre"))
                    break
        "pause":
            paused=bool(payload.get("value",false))
            pause_button.text="Reprendre" if paused else "Mettre en pause"
        "lock":
            locked=bool(payload.get("value",false))
            lock_button.text="Déverrouiller les meubles" if locked else "Verrouiller les meubles"
    queue_redraw()


func _save_local_scenes() -> void:
    var f:=FileAccess.open("user://ergolab-bac-a-sable.json",FileAccess.WRITE)
    if f!=null:
        f.store_string(JSON.stringify({"scenarios":scenes,"active_index":active_index}))
        f.close()

func _load_local_scenes() -> void:
    var path: String="user://ergolab-bac-a-sable.json"
    if not FileAccess.file_exists(path):return
    var f:=FileAccess.open(path,FileAccess.READ)
    if f==null:return
    var parsed:Variant=JSON.parse_string(f.get_as_text())
    f.close()
    if parsed is Dictionary and parsed.get("scenarios",[]) is Array and not parsed.get("scenarios",[]).is_empty():
        scenes=parsed.get("scenarios",[])
        active_index=clampi(int(parsed.get("active_index",0)),0,scenes.size()-1)
