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
var palette_open: bool = true
var show_blueprint: bool = false
var palette_panel: Control
var stage_panel: Control
var hint_label: Label
var viewport_initialized: bool = false
var walking: bool = false
var direction_facing: Vector2 = Vector2.DOWN
var animation_clock: float = 0.0
var camera_dragging: bool = false
var floor_mother: PackedVector2Array = PackedVector2Array([
    Vector2(123,705),Vector2(105,610),Vector2(106,480),Vector2(128,379),
    Vector2(176,291),Vector2(256,233),Vector2(374,206),Vector2(482,222),
    Vector2(564,269),Vector2(620,358),Vector2(615,701)
])
var floor_primary: PackedVector2Array = PackedVector2Array([
    Vector2(433,727),Vector2(825,727),Vector2(918,818),
    Vector2(944,965),Vector2(432,965)
])

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
    scenes = [
        {"name":"Exemple à modifier","notes":"Proposition pédagogique de mobilier ; le plan original ne contient pas d’implantation définitive.","objects":[
            {"uid":1,"type":"frigo","x":835.0,"y":274.0,"rot":0.0},
            {"uid":2,"type":"etagere","x":850.0,"y":346.0,"rot":0.0},
            {"uid":3,"type":"evier","x":927.0,"y":322.0,"rot":0.0},
            {"uid":4,"type":"table","x":861.0,"y":455.0,"rot":0.0},
            {"uid":5,"type":"cuisson","x":1125.0,"y":426.0,"rot":0.0},
            {"uid":6,"type":"sauteuse","x":1110.0,"y":490.0,"rot":0.0},
            {"uid":7,"type":"plonge","x":1030.0,"y":490.0,"rot":0.0},
            {"uid":8,"type":"chariot","x":965.0,"y":520.0,"rot":0.0},
            {"uid":9,"type":"four","x":1133.0,"y":530.0,"rot":0.0}
        ]},
        {"name":"Plan vierge","notes":"Départ sans mobilier : construisez votre propre scénario.","objects":[]}
    ]
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
    b.clip_text = true
    b.custom_minimum_size = Vector2(74,35)
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
    top.add_theme_stylebox_override("panel",_panel(Color("#FFF9F0")))
    top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    top.offset_bottom = 58
    top.clip_contents = true
    ui_root.add_child(top)
    var head := HBoxContainer.new()
    head.add_theme_constant_override("separation",7)
    top.add_child(head)
    var title := _label("ERGOLAB  /  CUISINE SCOLAIRE",15,INK)
    title.custom_minimum_size.x = 250
    title.autowrap_mode = TextServer.AUTOWRAP_OFF
    head.add_child(title)
    var material_button := _button("Matériel",_toggle_palette)
    material_button.custom_minimum_size.x = 104
    head.add_child(material_button)
    name_input = LineEdit.new()
    name_input.placeholder_text = "Pseudonyme"
    name_input.text = "Participant"
    name_input.custom_minimum_size = Vector2(112,35)
    name_input.add_theme_color_override("font_color",INK)
    name_input.add_theme_stylebox_override("normal",_panel(PAPER))
    name_input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    head.add_child(name_input)
    color_button = _button("●",_cycle_color)
    color_button.tooltip_text = "Changer la couleur de ton avatar"
    color_button.custom_minimum_size.x = 37
    head.add_child(color_button)
    head.add_child(_button("+ Salle",_new_room,true))
    room_input = LineEdit.new()
    room_input.placeholder_text = "Code de salle"
    room_input.custom_minimum_size = Vector2(111,35)
    room_input.add_theme_color_override("font_color",INK)
    room_input.add_theme_stylebox_override("normal",_panel(PAPER))
    room_input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    head.add_child(room_input)
    head.add_child(_button("Entrer",_join_room))
    head.add_child(_button("Inviter",_copy_link))
    var grow := Control.new()
    grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(grow)
    role_label = _label("HORS LIGNE",11,GREEN)
    role_label.custom_minimum_size.x = 88
    role_label.autowrap_mode = TextServer.AUTOWRAP_OFF
    role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    head.add_child(role_label)

    palette_panel = PanelContainer.new()
    palette_panel.name = "PaletteEquipements"
    palette_panel.add_theme_stylebox_override("panel",_panel(Color("#FFF9F0")))
    palette_panel.position = Vector2(13,73)
    palette_panel.size = Vector2(196,570)
    ui_root.add_child(palette_panel)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    palette_panel.add_child(scroll)
    var palette := VBoxContainer.new()
    palette.custom_minimum_size.x = 170
    palette.add_theme_constant_override("separation",4)
    scroll.add_child(palette)
    palette.add_child(_label("ÉQUIPEMENTS",14,ORANGE))
    palette.add_child(_label("Clique pour ajouter · Glisse pour déplacer",10,MUTED))
    var last_category := ""
    for entry in CATALOG:
        var category: String = str(entry["kind"])
        if last_category != category:
            last_category = category
            palette.add_child(_space(7))
            palette.add_child(_label(category.to_upper(),10,MUTED))
        var equipment_id: String = str(entry["id"])
        palette.add_child(_button("+  " + str(entry["label"]),func(): _spawn_equipment(equipment_id)))
    palette.add_child(_space(10))
    palette.add_child(_label("R : rotation · Suppr : retirer",10,MUTED))

    stage_panel = PanelContainer.new()
    stage_panel.name = "CarteAtelier"
    stage_panel.add_theme_stylebox_override("panel",_panel(Color("#FFF9F0")))
    stage_panel.clip_contents = true
    stage_panel.size = Vector2(208,336)
    ui_root.add_child(stage_panel)
    var controls := VBoxContainer.new()
    controls.add_theme_constant_override("separation",5)
    stage_panel.add_child(controls)
    controls.add_child(_label("AMÉNAGEMENT",12,ORANGE))
    scenario_picker = OptionButton.new()
    scenario_picker.item_selected.connect(_select_scenario)
    controls.add_child(scenario_picker)
    scenario_title = LineEdit.new()
    scenario_title.placeholder_text = "Nom de l'aménagement"
    scenario_title.add_theme_color_override("font_color",INK)
    scenario_title.add_theme_stylebox_override("normal",_panel(PAPER))
    scenario_title.text_submitted.connect(func(_v): _rename_scenario())
    controls.add_child(scenario_title)
    var scenario_buttons := HBoxContainer.new()
    controls.add_child(scenario_buttons)
    scenario_buttons.add_child(_button("Renommer",_rename_scenario))
    scenario_buttons.add_child(_button("Dupliquer",_duplicate_scenario))
    controls.add_child(_space(3))
    controls.add_child(_label("VUE",11,ORANGE))
    var view_buttons := HBoxContainer.new()
    controls.add_child(view_buttons)
    view_buttons.add_child(_button("Cuisine",_focus_kitchen))
    view_buttons.add_child(_button("Plan entier",_focus_all))
    var overlay_buttons := HBoxContainer.new()
    controls.add_child(overlay_buttons)
    overlay_buttons.add_child(_button("F2 : Plan",_toggle_blueprint))
    overlay_buttons.add_child(_button("Grille",_toggle_grid))
    controls.add_child(_space(3))
    pause_button = _button("Pause",_toggle_pause)
    lock_button = _button("Verrouiller",_toggle_lock)
    var facilitator := HBoxContainer.new()
    controls.add_child(facilitator)
    facilitator.add_child(pause_button)
    facilitator.add_child(lock_button)
    controls.add_child(_label("OBSERVATION",11,ORANGE))
    obs_line = LineEdit.new()
    obs_line.placeholder_text = "Ce qui gêne le travail…"
    obs_line.add_theme_color_override("font_color",INK)
    obs_line.add_theme_stylebox_override("normal",_panel(PAPER))
    obs_line.text_submitted.connect(func(_v): _add_observation())
    controls.add_child(obs_line)
    controls.add_child(_button("Noter le problème",_add_observation))
    people_label = _label("1 participant",10,MUTED)
    controls.add_child(people_label)

    var bottom := PanelContainer.new()
    bottom.name = "BarreÉtat"
    bottom.add_theme_stylebox_override("panel",_panel(DARK))
    bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    bottom.offset_top = -44
    ui_root.add_child(bottom)
    var bottom_bar := HBoxContainer.new()
    bottom.add_child(bottom_bar)
    connect_status = _label("",11,Color.WHITE)
    connect_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bottom_bar.add_child(connect_status)
    mini_status = _label("",11,Color("#DCE6DD"))
    mini_status.custom_minimum_size.x = 210
    mini_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    bottom_bar.add_child(mini_status)
    _refresh_scenarios()

func _toggle_palette() -> void:
    palette_open = not palette_open
    palette_panel.visible = palette_open

func _toggle_grid() -> void:
    show_grid = not show_grid
    queue_redraw()

func _toggle_blueprint() -> void:
    show_blueprint = not show_blueprint
    queue_redraw()

func _focus_kitchen() -> void:
    camera.position = Vector2(915,443)
    var s: Vector2 = get_viewport_rect().size
    var z: float = clampf(minf((s.y-120.0)/690.0,(s.x-370.0)/670.0),0.56,1.45)
    camera.zoom = Vector2.ONE*z
    zoom_override = z
    queue_redraw()

func _focus_all() -> void:
    camera.position = Vector2(786,542)
    var s: Vector2 = get_viewport_rect().size
    var z: float = clampf(minf((s.x-35.0)/1610.0,(s.y-100.0)/1100.0),0.35,1.1)
    camera.zoom = Vector2.ONE*z
    zoom_override = z
    queue_redraw()

func _resize() -> void:
    if camera == null or ui_root == null:
        return
    var screen: Vector2 = get_viewport_rect().size
    ui_root.size = screen
    palette_panel.position = Vector2(12,72)
    palette_panel.size = Vector2(196,minf(580.0,maxf(230.0,screen.y-143.0)))
    palette_panel.visible = palette_open and screen.x>790.0
    stage_panel.position = Vector2(screen.x-223.0,72)
    stage_panel.size = Vector2(210,minf(425.0,maxf(240.0,screen.y-147.0)))
    stage_panel.visible = screen.x>900.0
    if not viewport_initialized:
        viewport_initialized = true
        _focus_kitchen()
    queue_redraw()

func _reset_camera() -> void:
    _focus_kitchen()

func _cycle_color() -> void:
    color_index = (color_index+1)%AVATAR_COLORS.size()
    color_button.text = "●"
    color_button.add_theme_color_override("font_color",Color(AVATAR_COLORS[color_index]))
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
    var own: Dictionary = _my_avatar()
    var pushing_target: int = int(own.get("target",-1)) if str(own.get("action","libre"))=="pousser" else -1
    for obj in _objects():
        if int(obj.get("uid",-2))==pushing_target:
            continue
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
    animation_clock += delta
    var focused: Control = get_viewport().gui_get_focus_owner()
    var typing: bool = focused is LineEdit or focused is TextEdit
    var avatar: Dictionary = _my_avatar()
    var speed := 135.0
    if str(avatar.get("action","libre"))=="porter":speed=92.0
    if str(avatar.get("action","libre"))=="pousser":speed=76.0
    var direction := Vector2.ZERO
    if not typing:
        if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):direction.x-=1.0
        if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):direction.x+=1.0
        if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_UP):direction.y-=1.0
        if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):direction.y+=1.0
    else:
        has_waypoint=false
    if not direction.is_zero_approx():
        has_waypoint=false
        direction=direction.normalized()
    elif has_waypoint:
        if _my_pos().distance_to(waypoint)<9.0:
            has_waypoint=false
        else:
            direction=_my_pos().direction_to(waypoint)
    walking = false
    if not direction.is_zero_approx() and not paused and (not network.has_room() or network.connected):
        direction_facing = direction
        var origin: Vector2 = _my_pos()
        var target: Vector2 = origin+direction*speed*delta
        if not _collision(target):
            if not network.has_room() and str(avatar.get("action","libre"))=="pousser":
                var pushed_uid: int=int(avatar.get("target",-1))
                for obj in _objects():
                    if int(obj.get("uid",-2))==pushed_uid and str(obj.get("type",""))=="chariot":
                        var cart_next: Vector2=Vector2(float(obj.get("x",0)),float(obj.get("y",0)))+(target-origin)
                        if _inside_kitchen(cart_next):
                            obj["x"]=cart_next.x
                            obj["y"]=cart_next.y
                            if int(animation_clock*2.0)!=int((animation_clock-delta)*2.0):
                                _save_local_scenes()
                        break
            _me_update(target)
            walking=true
            move_elapsed+=delta
            if network.has_room() and move_elapsed>0.15:
                move_elapsed=0.0
                network.send_move(target.x,target.y)
        else:
            has_waypoint=false
    status_elapsed+=delta
    if status_elapsed>=0.17:
        status_elapsed=0.0
        var near_id: int = _nearest_equipment(115.0)
        if hint_label:
            var current_action: String = str(_my_avatar().get("action","libre"))
            if current_action!="libre":
                hint_label.text="ACTIVITÉ : " + current_action.to_upper()+"   ·   E pour terminer"
            elif near_id>=0:
                var nearest_name: String = "poste"
                for obj in _objects():
                    if int(obj.get("uid",-1))==near_id:
                        nearest_name=str(equipment_labels.get(str(obj.get("type","")),"poste"))
                        break
                hint_label.text="E  ·  Utiliser : " + nearest_name + "    |    R : tourner l'objet"
            else:
                hint_label.text="ZQSD / FLÈCHES pour marcher  ·  CLIC pour avancer  ·  E pour agir"
        if mini_status:
            mini_status.text = "%d agents    •    %.1f m" % [maxi(1,participants.size()),local_distance]
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
    if paused:
        _status("Simulation en pause")
        return
    var avatar: Dictionary = _my_avatar()
    if str(avatar.get("action","libre")) != "libre":
        _set_action("libre",-1)
        return
    var obj_idx: int = _nearest_equipment(115.0)
    if obj_idx < 0:
        _status("Approche-toi d'un équipement pour interagir.")
        return
    var obj: Dictionary = {}
    for item in _objects():
        if int(item.get("uid",-1))==obj_idx:
            obj = item
            break
    var equipment_type: String = str(obj.get("type",""))
    var action: String = "préparer"
    if equipment_type=="chariot":action="pousser"
    elif equipment_type in ["cuisson","sauteuse","marmite","four","friteuse"]:action="cuisiner"
    elif equipment_type in ["plonge","lave_mains"]:action="plonge"
    elif equipment_type in ["meuble_chaud"]:action="servir"
    elif equipment_type=="etagere":action="porter"
    elif equipment_type in ["evier"]:action="préparer"
    _set_action(action,obj_idx)

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
        pause_button.text="Reprendre" if paused else "Pause"

func _toggle_lock() -> void:
    if network.has_room():
        if network.role!="host":return
        network.send_lock(not locked)
    else:
        locked=not locked
    lock_button.text="Débloquer" if locked else "Bloquer"

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
    # La référence architecturale est un calque facultatif, PAS le décor du jeu.
    draw_rect(Rect2(-350,-320,2450,1850),Color("#C6D3C1"))
    # Cour, trotir et boulevard : repères du site, sans objets fictifs.
    draw_rect(Rect2(-80,65,740,1020),Color("#DCE6D2"))
    draw_colored_polygon(PackedVector2Array([Vector2(1293,-180),Vector2(1710,-180),Vector2(2030,1150),Vector2(1550,1150)]),Color("#78898B"))
    draw_colored_polygon(PackedVector2Array([Vector2(1230,-180),Vector2(1293,-180),Vector2(1550,1150),Vector2(1475,1150)]),Color("#D2CCB9"))
    for v in range(-2,12):
        var t: float = float(v)*150.0
        draw_line(Vector2(1490+t*0.22,t-150),Vector2(1520+t*0.22,t-96),Color(1,1,1,0.48),3.0)

    # Les réfectoires restent libres, comme sur le plan de projet non aménagé.
    _paint_floor(floor_mother,Color("#E9DCC4"),Color("#D4C09F"),"RÉFECTOIRE",Vector2(360,432),"MATERNELLE")
    _paint_floor(floor_primary,Color("#E9DCC4"),Color("#D4C09F"),"RÉFECTOIRE",Vector2(670,837),"ÉLÉMENTAIRE")
    _paint_floor(walk_poly,Color("#EBF0E8"),Color("#CBD9D0"),"CUISINE",Vector2(977,328),"ESPACE DE TRAVAIL")
    # Deux seuils de liaison. Le contour reste à confirmer sur un plan coté.
    _draw_door(Vector2(630,383),-0.44)
    _draw_door(Vector2(913,607),-0.65)
    if show_blueprint:
        draw_texture_rect(MAP,Rect2(0,0,1571,1088),false,Color(1,1,1,0.64))
        draw_string(ThemeDB.fallback_font,Vector2(814,140),"CALQUE ARCHITECTE · F2 POUR MASQUER",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("#97623A"))
    for o in _objects():
        _draw_equipment(o)
    if network.has_room():
        for person in participants:
            if bool(person.get("connected",true)):
                _draw_avatar(person)
    else:
        _draw_avatar({"id":"local","nickname":nickname if nickname!="" else "Moi","color":local_avatar.get("color",AVATAR_COLORS[color_index]),"avatar":local_avatar,"connected":true})
    if has_waypoint:
        draw_arc(waypoint,10.0,0,TAU,28,Color("#D8804A"),2.6,true)
        draw_circle(waypoint,3.0,Color("#D8804A"))
    _draw_interaction_hint()

func _draw_interaction_hint() -> void:
    var nearby: int=_nearest_equipment(115.0)
    var a: Dictionary=_my_avatar()
    var doing: String=str(a.get("action","libre"))
    if nearby<0 and doing=="libre":
        return
    var message: String="E : arrêter" if doing!="libre" else "E : interagir"
    if nearby>=0 and doing=="libre":
        for obj in _objects():
            if int(obj.get("uid",-1))==nearby:
                message="E : "+str(equipment_labels.get(str(obj.get("type","")),"utiliser"))
                break
    var location: Vector2=_my_pos()+Vector2(0,42)
    var font: Font=ThemeDB.fallback_font
    var width_text: float=font.get_string_size(message,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
    var box: Rect2=Rect2(location.x-width_text*0.5-12,location.y-15,width_text+24,27)
    draw_rect(box,Color("#24424DEB"))
    draw_rect(box,Color("#F0CC91"),false,1.2)
    draw_string(font,location+Vector2(-width_text*0.5,4),message,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)

func _paint_floor(poly: PackedVector2Array, base: Color, grout: Color, title: String, caption_at: Vector2, subtitle: String) -> void:
    draw_colored_polygon(poly,Color(0.10,0.19,0.18,0.18))
    draw_colored_polygon(poly,base)
    # Dalles en vue de dessus, sans grilles techniques rouges.
    var aabb: Rect2 = _poly_bounds(poly)
    var gap: float = 34.0 if title=="CUISINE" else 49.0
    var yy: float = floorf(aabb.position.y/gap)*gap
    while yy<aabb.end.y:
        var xx: float = floorf(aabb.position.x/gap)*gap
        while xx<aabb.end.x:
            var center: Vector2=Vector2(xx+gap*0.5,yy+gap*0.5)
            if Geometry2D.is_point_in_polygon(center,poly):
                var t: Rect2=Rect2(xx+2,yy+2,gap-4,gap-4)
                draw_rect(t,Color(base.r+0.018,base.g+0.018,base.b+0.018,0.75))
                draw_line(Vector2(xx+2,yy+gap-2),Vector2(xx+gap-2,yy+gap-2),Color(grout.r,grout.g,grout.b,0.40),1.0)
            xx += gap
        yy += gap
    # Murs physiques visibles : deux traits, une ombre et une plinthe.
    var count: int=poly.size()
    for k in range(count):
        var a: Vector2=poly[k]
        var b: Vector2=poly[(k+1)%count]
        draw_line(a+Vector2(3,5),b+Vector2(3,5),Color(0.12,0.17,0.17,0.18),19.0,true)
        draw_line(a,b,Color("#526B68"),17.0,true)
        draw_line(a,b,Color("#FFFDF6"),10.0,true)
        draw_line(a,b,Color("#A3B7AA"),1.7,true)
    var name_color: Color=Color("#6B8C83") if title=="CUISINE" else Color("#AD9275")
    draw_string(ThemeDB.fallback_font,caption_at,title,HORIZONTAL_ALIGNMENT_CENTER,-1,27,name_color)
    draw_string(ThemeDB.fallback_font,caption_at+Vector2(0,23),subtitle,HORIZONTAL_ALIGNMENT_CENTER,-1,13,Color(name_color.r,name_color.g,name_color.b,0.85))

func _poly_bounds(poly: PackedVector2Array) -> Rect2:
    var result: Rect2=Rect2(poly[0],Vector2.ZERO)
    for point in poly:
        result=result.expand(point)
    return result

func _draw_door(place: Vector2, angle: float) -> void:
    # Ouverture explicite sur les parois représentées. Position à confirmer.
    draw_set_transform(place,angle)
    draw_rect(Rect2(-24,-13,48,26),Color("#EBF0E8"))
    draw_line(Vector2(-22,8),Vector2(22,8),Color("#BBAD94"),2.4)
    draw_arc(Vector2(-22,9),40.0,-PI*0.49,0.0,18,Color("#BAA888"),1.7,true)
    draw_line(Vector2(-22,9),Vector2(-22,-30),Color("#B8A78D"),3.0,true)
    draw_set_transform(Vector2.ZERO)

func _draw_equipment(o: Dictionary) -> void:
    var id: String = str(o.get("type",""))
    var dimensions: Vector2 = equipment_sizes.get(id,Vector2(39,53))
    var center: Vector2 = Vector2(float(o.get("x",0)),float(o.get("y",0)))
    var angle: float = deg_to_rad(float(o.get("rot",0)))
    var extent: Vector2 = dimensions*0.5
    draw_set_transform(center,angle)
    var tile: Rect2 = Rect2(-extent,dimensions)
    draw_rect(Rect2(tile.position+Vector2(0,4)-Vector2(5,5),tile.size+Vector2(10,10)),Color(0.09,0.15,0.17,0.22))
    # Équipements illustrés directement par Godot, avec des attributs reconnaissables.
    var metal: Color=Color("#D6E0DC")
    var edge: Color=Color("#708E90")
    if id in ["table","etagere","meuble_chaud"]:
        metal=Color("#D4E4E1") if id=="table" else Color("#CABAA2") if id=="etagere" else Color("#D6BFA7")
    if id in ["cuisson","sauteuse","marmite","four","friteuse"]:
        metal=Color("#B6C6CC")
    draw_rect(tile,metal)
    draw_rect(tile,edge,false,2.0)
    draw_line(tile.position+Vector2(4,5),tile.position+Vector2(tile.size.x-4,5),Color(1,1,1,0.60),2.0)
    var iw: float=extent.x
    var ih: float=extent.y
    match id:
        "chariot":
            draw_rect(Rect2(-iw+4,-ih+4,dimensions.x-8,dimensions.y-8),Color("#9FC1C5"))
            for x in [-iw+2,iw-2]:
                for y in [-ih+2,ih-2]:draw_circle(Vector2(x,y),3.5,Color("#354D54"))
            draw_line(Vector2(-iw-4,-ih),Vector2(-iw-4,ih),Color("#7C8F94"),3.0)
        "table":
            draw_rect(Rect2(-iw+5,-ih+8,dimensions.x-10,dimensions.y-16),Color("#C2D0CB"))
            draw_rect(Rect2(-iw+6,-ih+10,dimensions.x-12,minf(24.0,ih*0.7)),Color("#CBAC78"))
            draw_line(Vector2(-iw+9,0),Vector2(iw-9,0),Color(1,1,1,0.62),2.0)
        "frigo":
            draw_rect(Rect2(-iw+4,-ih+4,dimensions.x-8,dimensions.y-8),Color("#F4F6EE"))
            draw_line(Vector2(-iw+2,0),Vector2(iw-2,0),Color("#80989B"),2.2)
            draw_rect(Rect2(iw-8,-ih*0.7,3,ih*0.5),Color("#526D70"))
            draw_rect(Rect2(iw-8,ih*0.12,3,ih*0.42),Color("#526D70"))
        "etagere":
            for yy in range(1,4):
                var bar_y: float=-ih+yy*dimensions.y/4.0
                draw_line(Vector2(-iw+3,bar_y),Vector2(iw-3,bar_y),Color("#92785C"),4.0)
        "evier", "plonge", "lave_mains":
            var basins: int=3 if id=="plonge" else 2 if id=="evier" else 1
            for j in range(basins):
                var yy: float=-ih+float(j+0.5)*dimensions.y/float(basins)
                var r: float=minf(iw-4.0,dimensions.y/float(basins)*0.38)
                draw_circle(Vector2(0,yy),maxf(4.0,r),Color("#88B5C1"))
                draw_arc(Vector2(0,yy),maxf(4.0,r),0.0,TAU,18,Color("#5A8190"),2.0,true)
                draw_circle(Vector2(0,yy),2.1,Color("#E4F0ED"))
        "cuisson", "sauteuse", "marmite", "four", "friteuse":
            if id=="four":
                draw_rect(Rect2(-iw+6,-ih+7,dimensions.x-12,dimensions.y-14),Color("#445D68"))
                for y in range(-2,3):
                    draw_line(Vector2(-iw+10,float(y)*5),Vector2(iw-10,float(y)*5),Color("#D9E3DB"),1.5)
            elif id=="friteuse":
                for xx in [-iw*0.5,iw*0.5]:
                    draw_rect(Rect2(xx-6,-ih+8,12,dimensions.y-16),Color("#566F7B"))
                    draw_line(Vector2(xx-5,0),Vector2(xx+5,0),Color("#E8B870"),2.0)
            else:
                for xx in [-iw*0.52,iw*0.52]:
                    var rr: float=minf(7.0,ih*0.44)
                    draw_circle(Vector2(xx,0),rr,Color("#566C75"))
                    draw_arc(Vector2(xx,0),rr-2.0,0.0,TAU,18,Color("#D4E1DB"),2.0,true)
                    draw_circle(Vector2(xx,0),2.0,Color("#DA9B65"))
        "meuble_chaud":
            for yy in [-ih*0.52,0.0,ih*0.52]:
                draw_line(Vector2(-iw+5,yy),Vector2(iw-5,yy),Color("#886F5D"),2.5)
        "eplucheuse":
            draw_circle(Vector2(0,0),minf(iw,ih)*0.70,Color("#708D94"))
            draw_circle(Vector2(0,0),minf(iw,ih)*0.37,Color("#B8C8CB"))
    if int(o.get("uid",-1))==selected_uid:
        draw_rect(tile.grow(9),Color("#E08048"),false,3.0)
        draw_circle(Vector2(iw+9,-ih-7),4.0,Color("#E08048"))
    draw_set_transform(Vector2.ZERO)

func _draw_avatar(person: Dictionary) -> void:
    var av: Dictionary=person.get("avatar",{})
    var pos: Vector2=Vector2(float(av.get("x",981)),float(av.get("y",439)))
    var tint: Color=Color(str(person.get("color",AVATAR_COLORS[0])))
    var label: String=str(person.get("nickname","Agent"))
    var mine: bool = (str(person.get("id",""))==network.peer_id) if network.has_room() else true
    var action: String=str(av.get("action","libre"))
    if show_paths:
        var trail: Array=av.get("trail",[])
        for k in range(1,trail.size()):
            var a: Array=trail[k-1]
            var b: Array=trail[k]
            draw_line(Vector2(float(a[0]),float(a[1])),Vector2(float(b[0]),float(b[1])),Color(tint.r,tint.g,tint.b,0.50),2.7,true)
    var facing: Vector2=direction_facing if mine else Vector2.DOWN
    if not mine:
        var trace: Array=av.get("trail",[])
        if trace.size()>1:
            var tail: Array=trace[trace.size()-1]
            var before: Array=trace[trace.size()-2]
            var diff: Vector2=Vector2(float(tail[0])-float(before[0]),float(tail[1])-float(before[1]))
            if diff.length()>1.0:facing=diff.normalized()
    var swing: float=sin(animation_clock*14.0)*5.0 if mine and walking else 0.0
    draw_circle(pos+Vector2(3,10),19.0,Color(0,0,0,0.19))
    draw_set_transform(pos,Vector2.DOWN.angle_to(facing))
    # Silhouette d'agent vue de dessus, avec démarche et direction lisible.
    draw_line(Vector2(-5,8),Vector2(-6,22+swing),Color("#3B5962"),7.0,true)
    draw_line(Vector2(5,8),Vector2(6,22-swing),Color("#3B5962"),7.0,true)
    draw_line(Vector2(-8,-3),Vector2(-17,10-swing*0.35),Color("#D5A57D"),6.0,true)
    draw_line(Vector2(8,-3),Vector2(17,10+swing*0.35),Color("#D5A57D"),6.0,true)
    draw_circle(Vector2(0,2),13.0,tint)
    draw_rect(Rect2(-7,-2,14,17),Color("#F5E7CD"))
    draw_line(Vector2(-7,13),Vector2(7,13),Color("#DDCBAC"),1.8)
    draw_circle(Vector2(0,-9),9.0,Color("#E5B58C"))
    # Couvre-chef et direction du regard.
    draw_arc(Vector2(0,-11),9.0,PI,TAU,16,Color("#3D4A4C"),4.5,true)
    draw_circle(Vector2(-3,-13),1.4,Color("#544136"))
    draw_circle(Vector2(3,-13),1.4,Color("#544136"))
    if action in ["porter","livrer"]:
        draw_rect(Rect2(-11,-34,22,13),Color("#C58C50"))
        draw_line(Vector2(-10,-28),Vector2(10,-28),Color("#72563F"),2.0)
    elif action=="pousser":
        draw_line(Vector2(-12,-23),Vector2(12,-23),Color("#476778"),4.0)
    elif action=="cuisiner":
        draw_circle(Vector2(15,-23),7.0,Color("#F3A84E"))
        draw_circle(Vector2(17,-26),4.0,Color("#D87B42"))
    elif action in ["plonge","nettoyer"]:
        draw_arc(Vector2(15,-25),7.0,0.0,TAU,20,Color("#62B6CD"),2.6,true)
    elif action in ["préparer","servir"]:
        draw_rect(Rect2(-6,-29,13,7),Color("#D7B37E"))
    draw_set_transform(Vector2.ZERO)
    if mine:
        draw_arc(pos,22.0,0,TAU,35,Color("#F3A45C"),2.8,true)
    var name_offset: Vector2=pos+Vector2(0,-34)
    var font: Font=ThemeDB.fallback_font
    var name_width: float=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
    draw_rect(Rect2(name_offset+Vector2(-name_width*0.5-6,-17),Vector2(name_width+12,21)),Color("#253B40CC"))
    draw_string(font,name_offset+Vector2(-name_width*0.5,0),label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
    if action!="libre":
        draw_string(font,pos+Vector2(19,19),action,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#8A4F2C"))

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed:
            _zoom_at_pointer(1.13)
            get_viewport().set_input_as_handled()
        elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            _zoom_at_pointer(1.0/1.13)
            get_viewport().set_input_as_handled()
        elif event.button_index==MOUSE_BUTTON_MIDDLE:
            camera_dragging=event.pressed
            get_viewport().set_input_as_handled()
        elif event.button_index==MOUSE_BUTTON_LEFT:
            if event.pressed:
                get_viewport().gui_release_focus()
                var wp: Vector2=get_global_mouse_position()
                var index: int=_item_at(wp)
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
        if camera_dragging:
            camera.position-=event.relative/camera.zoom.x
            queue_redraw()
            get_viewport().set_input_as_handled()
        elif dragging:
            var mousepos: Vector2=get_global_mouse_position()+drag_offset
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
        elif event.keycode==KEY_F2:_toggle_blueprint()
        elif event.keycode==KEY_F:_focus_kitchen()
        elif event.keycode==KEY_ESCAPE:_set_action("libre",-1)

func _zoom_at_pointer(multiplier: float) -> void:
    var old: float = camera.zoom.x
    var new_zoom: float = clampf(old*multiplier,0.34,2.65)
    var screen_delta: Vector2 = get_viewport().get_mouse_position()-get_viewport_rect().size*0.5
    camera.position += screen_delta*(1.0/old-1.0/new_zoom)
    camera.zoom=Vector2.ONE*new_zoom
    zoom_override=new_zoom
    queue_redraw()

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
    pause_button.text="Reprendre" if paused else "Pause"
    lock_button.text="Débloquer" if locked else "Bloquer"
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
                    participants[i]["avatar"]["target"]=payload.get("target",-1)
                    break
        "pause":
            paused=bool(payload.get("value",false))
            pause_button.text="Reprendre" if paused else "Pause"
        "lock":
            locked=bool(payload.get("value",false))
            lock_button.text="Débloquer" if locked else "Bloquer"
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
