extends Control
## Interface Godot 4 : atelier de simulation ergonomique, première itération.
## Les scénarios sont enregistrés localement dans le navigateur ; la synchronisation
## simultanée entre navigateurs nécessite un serveur et sera un module distinct.

const CanvasScript = preload("res://scripts/map_canvas.gd")
const NetworkScript = preload("res://scripts/network_room.gd")
const STORAGE := "user://ergolab_scenarios.json"
const BG := Color("#EEEAE3")
const PANEL := Color("#FFFDF9")
const INK := Color("#25363C")
const SUB := Color("#708185")
const ORANGE := Color("#D56C3E")
const TYPES := [
    {"id":"chariot", "title":"Chariot", "w":29.0,"h":17.0, "group":"Logistique"},
    {"id":"evier", "title":"Évier et bacs", "w":31.0,"h":85.0, "group":"Préparation"},
    {"id":"lave_mains", "title":"Lave-mains", "w":22.0,"h":46.0, "group":"Préparation"},
    {"id":"plonge", "title":"Meuble de plonge", "w":31.0,"h":181.0, "group":"Entretien"},
    {"id":"etagere", "title":"Étagère", "w":34.0,"h":106.0, "group":"Stockage"},
    {"id":"table", "title":"Table de travail", "w":28.0,"h":83.0, "group":"Préparation"},
    {"id":"frigo", "title":"Réfrigérateur", "w":35.0,"h":85.0, "group":"Stockage"},
    {"id":"sauteuse", "title":"Sauteuse", "w":41.0,"h":43.0, "group":"Cuisson"},
    {"id":"cuisson", "title":"Table de cuisson", "w":41.0,"h":27.0, "group":"Cuisson"},
    {"id":"marmite", "title":"Marmite", "w":41.0,"h":34.0, "group":"Cuisson"},
    {"id":"friteuse", "title":"Friteuse", "w":41.0,"h":37.0, "group":"Cuisson"},
    {"id":"four", "title":"Four", "w":43.0,"h":53.0, "group":"Cuisson"},
    {"id":"meuble_chaud", "title":"Meuble chaud", "w":32.0,"h":74.0, "group":"Cuisson"},
    {"id":"eplucheuse", "title":"Éplucheuse à pommes de terre", "w":35.0,"h":37.0, "group":"Préparation"}
]

var canvas: Control
var scenario_select: OptionButton
var scenario_name_field: LineEdit
var selection_label: Label
var analysis_label: Label
var info_label: Label
var status_label: Label
var note_box: TextEdit
var grid_button: CheckButton
var sim_button: CheckButton
var scenario_store: Array = []
var active_index: int = 0
var is_loading: bool = false
var selected: Dictionary = {}
var avatar_prompt: ConfirmationDialog
var avatar_name_input: LineEdit
var network: Node
var name_field: LineEdit
var room_field: LineEdit
var color_picker: OptionButton
var room_details: Label
var participants_label: Label
var pause_control: Button
var lock_control: Button
var action_picker: OptionButton
var room_revision: int = 1
var room_players: Array = []
var session_paused: bool = false
var session_locked: bool = false
var note_timer: Timer
const ROOM_COLORS := ["#CE6D3C", "#3C82B5", "#639F76", "#9B72BA", "#C59D40", "#D06E89", "#3B968D", "#8A7B63"]
const ROOM_ACTIONS := ["libre", "préparer", "cuisiner", "porter", "pousser", "plonge", "servir", "attendre", "nettoyer", "livrer"]

func _ready() -> void:
    get_window().title = "ErgoLab · Simulation du travail"
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    network = NetworkScript.new()
    add_child(network)
    network.session_ready.connect(_on_session_ready)
    network.state_received.connect(_on_shared_state)
    network.message_received.connect(_on_shared_event)
    network.connection_status.connect(_set_status)
    note_timer = Timer.new()
    note_timer.one_shot = true
    note_timer.wait_time = 1.0
    add_child(note_timer)
    note_timer.timeout.connect(_save_data)
    _construct_interface()
    _load_data()
    _refresh_scenarios()
    _activate_scenario(active_index, true)
    _set_status("Projet chargé · maquette fondée sur le plan du dossier")
    var from_url: String = network.room_from_url()
    if not from_url.is_empty():
        room_field.text = from_url
        room_details.text = "Invitation reçue · choisis ton pseudonyme et rejoins la salle."

func _panel_style(fill: Color = PANEL, line: Color = Color("#DDDCD4")) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = fill
    s.border_color = line
    s.set_border_width_all(1)
    s.set_corner_radius_all(8)
    s.content_margin_left = 10
    s.content_margin_right = 10
    s.content_margin_top = 8
    s.content_margin_bottom = 8
    return s

func _label(txt: String, font_size: int = 14, color: Color = INK) -> Label:
    var v := Label.new()
    v.text = txt
    v.add_theme_font_size_override("font_size", font_size)
    v.add_theme_color_override("font_color", color)
    v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return v

func _button(txt: String, action: Callable, secondary: bool = true) -> Button:
    var v := Button.new()
    v.text = txt
    v.custom_minimum_size.y = 34
    v.add_theme_font_size_override("font_size", 13)
    v.add_theme_color_override("font_color", INK if secondary else Color.WHITE)
    var st := _panel_style(PANEL if secondary else ORANGE, Color("#DBD9D1") if secondary else ORANGE)
    st.set_corner_radius_all(7)
    v.add_theme_stylebox_override("normal", st)
    v.add_theme_stylebox_override("hover", _panel_style(Color("#F2E4D8") if secondary else Color("#BE5B33")))
    v.pressed.connect(action)
    return v

func _space(h: float = 12.0) -> Control:
    var v := Control.new()
    v.custom_minimum_size.y = h
    return v

func _construct_interface() -> void:
    var body := VBoxContainer.new()
    body.add_theme_constant_override("separation", 0)
    add_child(body)
    body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var top := PanelContainer.new()
    top.custom_minimum_size.y = 68
    top.add_theme_stylebox_override("panel", _panel_style(PANEL))
    body.add_child(top)
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 12)
    header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(header)
    var brand := VBoxContainer.new()
    brand.custom_minimum_size.x = 335.0
    brand.add_theme_constant_override("separation", 2)
    header.add_child(brand)
    var title_label := _label("ERGOLAB  /  ATELIER NUMÉRIQUE", 17, INK)
    title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
    brand.add_child(title_label)
    var subtitle := _label("Conception participative · Cuisine scolaire", 11, SUB)
    subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
    brand.add_child(subtitle)
    var filler := Control.new()
    filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(filler)
    var zoom_minus := _button("−",func(): canvas.zoom_by(0.82))
    zoom_minus.custom_minimum_size.x = 52
    header.add_child(zoom_minus)
    var zoom_plus := _button("+",func(): canvas.zoom_by(1.22))
    zoom_plus.custom_minimum_size.x = 52
    header.add_child(zoom_plus)
    var fit_button := _button("Cadrer",func(): canvas.fit_to_view())
    fit_button.custom_minimum_size.x = 80
    header.add_child(fit_button)
    var export_button := _button("Copier JSON",_copy_json)
    export_button.custom_minimum_size.x = 115
    header.add_child(export_button)

    var room_bar := PanelContainer.new()
    room_bar.custom_minimum_size.y = 54
    room_bar.add_theme_stylebox_override("panel", _panel_style(Color("#E9EEE9")))
    body.add_child(room_bar)
    var room_controls := HBoxContainer.new()
    room_controls.add_theme_constant_override("separation",8)
    room_bar.add_child(room_controls)
    var room_title := _label("SALLES EN DIRECT",12,ORANGE)
    room_title.custom_minimum_size.x = 120
    room_title.autowrap_mode = TextServer.AUTOWRAP_OFF
    room_controls.add_child(room_title)
    name_field = LineEdit.new()
    name_field.custom_minimum_size.x = 140
    name_field.placeholder_text = "Ton pseudonyme"
    name_field.text = "Participant"
    room_controls.add_child(name_field)
    color_picker = OptionButton.new()
    color_picker.custom_minimum_size.x = 90
    for i in range(ROOM_COLORS.size()):
        color_picker.add_item("Couleur " + str(i+1),i)
    room_controls.add_child(color_picker)
    var create_button := _button("Créer une salle",_create_room,false)
    create_button.custom_minimum_size.x = 120
    room_controls.add_child(create_button)
    room_field = LineEdit.new()
    room_field.placeholder_text = "Code de salle"
    room_field.custom_minimum_size.x = 142
    room_controls.add_child(room_field)
    var join_button := _button("Rejoindre",_join_room)
    join_button.custom_minimum_size.x = 85
    room_controls.add_child(join_button)
    var share_button := _button("Copier le lien",_copy_room_link)
    share_button.custom_minimum_size.x = 116
    room_controls.add_child(share_button)
    room_details = _label("Mode local · aucune salle connectée",11,SUB)
    room_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    room_controls.add_child(room_details)

    var columns := HBoxContainer.new()
    columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
    columns.add_theme_constant_override("separation", 0)
    body.add_child(columns)

    var left := PanelContainer.new()
    left.custom_minimum_size.x = 248
    left.add_theme_stylebox_override("panel", _panel_style(PANEL))
    columns.add_child(left)
    var left_scroll := ScrollContainer.new()
    left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left.add_child(left_scroll)
    var palette := VBoxContainer.new()
    palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    palette.custom_minimum_size.x = 220.0
    palette.add_theme_constant_override("separation", 5)
    left_scroll.add_child(palette)
    palette.add_child(_label("BIBLIOTHÈQUE", 13, ORANGE))
    palette.add_child(_label("Matériel fourni page 6", 12, SUB))
    palette.add_child(_space(8))
    var groups := ["Logistique", "Stockage", "Préparation", "Cuisson", "Entretien"]
    for grp in groups:
        palette.add_child(_label(grp.to_upper(), 11, SUB))
        for entry in TYPES:
            if entry["group"] == grp:
                var type_id: String = entry["id"]
                palette.add_child(_button("＋  " + str(entry["title"]),func(): canvas.add_equipment(type_id)))
        palette.add_child(_space(9))
    palette.add_child(_label("PARTICIPANTS", 11, SUB))
    palette.add_child(_button("＋  Ajouter un avatar",_ask_avatar,false))
    palette.add_child(_space(15))
    palette.add_child(_label("Dessin original en référence", 11, SUB))

    canvas = CanvasScript.new()
    canvas.set_catalog(TYPES)
    canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
    canvas.custom_minimum_size = Vector2(320, 350)
    canvas.selection_changed.connect(_on_selection)
    canvas.content_changed.connect(_on_changed)
    canvas.avatar_motion.connect(_on_avatar_motion)
    columns.add_child(canvas)

    var right := PanelContainer.new()
    right.custom_minimum_size.x = 296
    right.add_theme_stylebox_override("panel", _panel_style(PANEL))
    columns.add_child(right)
    var right_scroll := ScrollContainer.new()
    right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    right.add_child(right_scroll)
    var controls := VBoxContainer.new()
    controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    controls.custom_minimum_size.x = 266.0
    controls.add_theme_constant_override("separation", 7)
    right_scroll.add_child(controls)
    controls.add_child(_label("SCÉNARIOS D'AMÉNAGEMENT", 12, ORANGE))
    scenario_select = OptionButton.new()
    scenario_select.custom_minimum_size.y = 36
    scenario_select.item_selected.connect(_activate_scenario)
    controls.add_child(scenario_select)
    var commands := HBoxContainer.new()
    controls.add_child(commands)
    var plus := _button("Dupliquer",_clone_scenario)
    plus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    commands.add_child(plus)
    commands.add_child(_button("Supprimer",_remove_scenario))
    scenario_name_field = LineEdit.new()
    scenario_name_field.placeholder_text = "Nom du scénario"
    scenario_name_field.text_submitted.connect(func(_value): _rename_scenario())
    controls.add_child(scenario_name_field)
    controls.add_child(_button("Renommer",_rename_scenario))
    controls.add_child(_space(7))

    controls.add_child(_label("AFFICHAGE ET SIMULATION", 12, ORANGE))
    grid_button = CheckButton.new()
    grid_button.text = "Grille métrique"
    grid_button.button_pressed = true
    grid_button.toggled.connect(func(enabled): canvas.grid_enabled=enabled; canvas.queue_redraw())
    controls.add_child(grid_button)
    sim_button = CheckButton.new()
    sim_button.text = "Enregistrer les trajets des avatars"
    sim_button.toggled.connect(func(enabled): canvas.simulation_mode=enabled; _update_analysis())
    controls.add_child(sim_button)
    controls.add_child(_button("Effacer les trajets",func(): canvas.clear_trails()))
    controls.add_child(_space(8))
    controls.add_child(_label("ACTIONS DE TON AVATAR", 12, ORANGE))
    controls.add_child(_label("Clique dans le plan, puis déplace-toi avec ZQSD / WASD / flèches.",11,SUB))
    action_picker = OptionButton.new()
    for i in range(ROOM_ACTIONS.size()):
        action_picker.add_item(ROOM_ACTIONS[i].capitalize(), i)
    controls.add_child(action_picker)
    controls.add_child(_button("Effectuer l'action au poste le plus proche",_do_avatar_action,false))
    controls.add_child(_space(7))
    controls.add_child(_label("ANIMATION DE SALLE",12,ORANGE))
    pause_control = _button("Mettre en pause",_toggle_pause)
    pause_control.disabled = true
    controls.add_child(pause_control)
    lock_control = _button("Verrouiller l'aménagement",_toggle_lock)
    lock_control.disabled = true
    controls.add_child(lock_control)
    participants_label = _label("Ouvre une salle pour voir les agents connectés.",11,SUB)
    controls.add_child(participants_label)
    controls.add_child(_space(8))

    controls.add_child(_label("OBJET SÉLECTIONNÉ", 12, ORANGE))
    selection_label = _label("Clique sur un équipement ou un avatar", 12, SUB)
    controls.add_child(selection_label)
    var rotate_buttons := HBoxContainer.new()
    controls.add_child(rotate_buttons)
    rotate_buttons.add_child(_button("↶ 90°",func():canvas.rotate_selection(-90.0)))
    rotate_buttons.add_child(_button("↷ 90°",func():canvas.rotate_selection(90.0)))
    rotate_buttons.add_child(_button("Copier",func():canvas.duplicate_selection()))
    controls.add_child(_button("Retirer l'objet",func():canvas.delete_selection()))
    controls.add_child(_space(7))

    controls.add_child(_label("INDICATEURS EXPLORATOIRES", 12, ORANGE))
    analysis_label = _label("", 13, INK)
    controls.add_child(analysis_label)
    controls.add_child(_label("Les collisions sont estimées par rectangles non orientés ; elles ne constituent pas une évaluation validée des risques.",11,SUB))
    controls.add_child(_space(7))
    controls.add_child(_label("OBSERVATIONS DE GROUPE", 12, ORANGE))
    note_box = TextEdit.new()
    note_box.custom_minimum_size.y = 100
    note_box.placeholder_text = "Déplacements, coactivité, contraintes et remarques des agents…"
    note_box.text_changed.connect(_on_notes_changed)
    controls.add_child(note_box)
    controls.add_child(_space(8))
    controls.add_child(_button("Enregistrer le scénario",_save_data,false))
    info_label = _label("Mode local : sauvegarde dans ce navigateur. Salle partagée : sauvegarde Neon.",11,SUB)
    controls.add_child(info_label)
    _update_analysis()

    var bottom := PanelContainer.new()
    bottom.custom_minimum_size.y = 37
    bottom.add_theme_stylebox_override("panel", _panel_style(PANEL))
    body.add_child(bottom)
    var foot := HBoxContainer.new()
    bottom.add_child(foot)
    status_label = _label("Prêt", 12, SUB)
    status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
    status_label.custom_minimum_size.x = 320.0
    foot.add_child(status_label)
    var foot_fill := Control.new()
    foot_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    foot.add_child(foot_fill)
    var foot_help := _label("Plan : cliquer-déplacer · Tourner : R · Zoom : molette · Agent : flèches ou WASD",11,SUB)
    foot_help.autowrap_mode = TextServer.AUTOWRAP_OFF
    foot_help.custom_minimum_size.x = 565.0
    foot.add_child(foot_help)

    avatar_prompt = ConfirmationDialog.new()
    avatar_prompt.title = "Nouvel agent virtuel"
    avatar_prompt.dialog_text = "Choisis le nom qui apparaîtra à côté de l'avatar."
    avatar_name_input = LineEdit.new()
    avatar_name_input.placeholder_text = "Ex. Agent de préparation"
    avatar_prompt.get_vbox().add_child(avatar_name_input)
    avatar_name_input.custom_minimum_size = Vector2(300,34)
    avatar_prompt.confirmed.connect(_add_avatar)
    add_child(avatar_prompt)

func _default_store() -> Array:
    return [
        {"name":"Scénario A · vierge", "objects":[], "notes":"Aménagement de départ. Ajouter les équipements de la page 6."},
        {"name":"Scénario B · variante", "objects":[], "notes":"Comparer une autre implantation à la configuration A."}
    ]

func _load_data() -> void:
    scenario_store = _default_store()
    active_index = 0
    if FileAccess.file_exists(STORAGE):
        var file := FileAccess.open(STORAGE,FileAccess.READ)
        if file != null:
            var parsed: Variant = JSON.parse_string(file.get_as_text())
            if parsed is Dictionary and parsed.has("scenarios") and parsed["scenarios"] is Array and not parsed["scenarios"].is_empty():
                scenario_store = parsed["scenarios"]
                active_index = clampi(int(parsed.get("active",0)),0,scenario_store.size()-1)

func _save_data() -> void:
    if is_loading:
        return
    _sync_current()
    if network.has_room():
        if network.connected:
            network.send_layout(scenario_store,active_index,room_revision)
            _set_status("Envoi des modifications au groupe…")
        else:
            _set_status("Hors ligne : modifications non synchronisées")
        return
    var file := FileAccess.open(STORAGE,FileAccess.WRITE)
    if file == null:
        _set_status("Impossible d'enregistrer dans ce navigateur")
        return
    file.store_string(JSON.stringify({"version":1,"active":active_index,"scenarios":scenario_store},"  "))
    file.close()
    _set_status("Modifications enregistrées dans le navigateur")

func _sync_current() -> void:
    if scenario_store.is_empty() or active_index < 0 or active_index >= scenario_store.size():
        return
    scenario_store[active_index]["objects"] = canvas.export_objects()
    scenario_store[active_index]["notes"] = note_box.text

func _refresh_scenarios() -> void:
    scenario_select.clear()
    for i in range(scenario_store.size()):
        scenario_select.add_item(str(scenario_store[i].get("name","Scénario")),i)
    if not scenario_store.is_empty():
        scenario_select.select(active_index)

func _activate_scenario(index: int, skip_sync: bool = false) -> void:
    if index < 0 or index >= scenario_store.size():
        return
    if not is_loading and not skip_sync:
        _sync_current()
    active_index = index
    is_loading = true
    var current: Dictionary = scenario_store[index]
    if network.has_room():
        _render_room_objects(current.get("objects",[]))
    else:
        canvas.set_objects(current.get("objects",[]))
    scenario_name_field.text = str(current.get("name","Scénario"))
    note_box.text = str(current.get("notes",""))
    scenario_select.select(index)
    is_loading = false
    _update_analysis()
    _save_data()

func _clone_scenario() -> void:
    _sync_current()
    var obj: Dictionary = scenario_store[active_index].duplicate(true)
    obj["name"] = str(obj.get("name","Scénario")) + " · copie"
    scenario_store.append(obj)
    is_loading = true
    active_index = scenario_store.size()-1
    _refresh_scenarios()
    is_loading = false
    _activate_scenario(active_index)

func _remove_scenario() -> void:
    if scenario_store.size() <= 1:
        _set_status("Conserver au moins un scénario")
        return
    scenario_store.remove_at(active_index)
    active_index = mini(active_index,scenario_store.size()-1)
    is_loading = true
    _refresh_scenarios()
    is_loading = false
    _activate_scenario(active_index, true)

func _rename_scenario() -> void:
    var new_name: String = scenario_name_field.text.strip_edges()
    if new_name.is_empty():
        return
    scenario_store[active_index]["name"] = new_name
    _refresh_scenarios()
    _save_data()

func _on_selection(item: Dictionary) -> void:
    selected = item
    if item.is_empty():
        selection_label.text = "Aucun objet sélectionné"
        return
    var typ: String = str(item.get("type",""))
    var label: String = str(item.get("name","Avatar")) if typ == "avatar" else typ.capitalize()
    for entry in TYPES:
        if entry["id"] == typ:
            label = str(entry["title"])
    selection_label.text = "%s\nPosition : %.1f m, %.1f m\nRotation : %d°" % [label,float(item.get("x",0))/canvas.PIXELS_PER_METER,float(item.get("y",0))/canvas.PIXELS_PER_METER,int(item.get("rot",0))]

func _on_changed() -> void:
    _update_analysis()
    _save_data()

func _on_notes_changed() -> void:
    if not is_loading:
        note_timer.start()

func _update_analysis() -> void:
    if canvas == null:
        return
    var stats: Dictionary = canvas.analyze()
    if analysis_label != null:
        analysis_label.text = "Équipements : %d\nAvatars : %d\nChevauchements possibles : %d\nTrajets enregistrés : %.1f m" % [stats["equipments"],stats["avatars"],stats["overlaps"],stats["distance_m"]]

func _copy_json() -> void:
    _sync_current()
    DisplayServer.clipboard_set(JSON.stringify({"version":1,"scenarios":scenario_store},"  "))
    _set_status("Scénarios copiés en JSON dans le presse-papiers")

func _ask_avatar() -> void:
    if network.has_room():
        _set_status("Chaque participant possède son avatar personnel : invite-le avec le lien de salle")
        return
    avatar_name_input.text = "Agent %d" % (canvas.analyze()["avatars"] + 1)
    avatar_prompt.popup_centered(Vector2i(390,190))

func _add_avatar() -> void:
    var txt: String = avatar_name_input.text.strip_edges()
    if txt.is_empty():
        txt = "Agent"
    canvas.add_avatar(txt)

func _set_status(value: String) -> void:
    if status_label != null:
        status_label.text = value


# MODE MULTIJOUEUR
func _create_room() -> void:
    network.start_new(name_field.text,ROOM_COLORS[color_picker.selected])

func _join_room() -> void:
    var code := room_field.text.strip_edges().to_lower()
    if code.is_empty():
        _set_status("Indique le code de la salle")
        return
    network.enter_room(code,name_field.text,ROOM_COLORS[color_picker.selected])

func _copy_room_link() -> void:
    network.copy_link()
    _set_status("Lien de la salle copié" if network.has_room() else "Crée ou rejoins d'abord une salle")

func _on_session_ready(data: Dictionary) -> void:
    room_details.text = "Salle : " + network.room + (" · animateur" if network.role=="host" else " · participant")
    room_field.text = network.room
    pause_control.disabled = network.role != "host"
    lock_control.disabled = network.role != "host"
    var snap: Variant = data.get("snapshot",{})
    if snap is Dictionary:
        _on_shared_state(snap)

func _player_uid(p: Dictionary) -> int:
    return absi(str(p.get("id","")).hash()) + 900000000

func _render_room_objects(equipment: Array) -> void:
    var participants: Array = []
    for p in room_players:
        var item: Dictionary = p.duplicate(true)
        item["uid"] = _player_uid(p)
        participants.append(item)
    canvas.set_live_objects(equipment,participants,network.my_avatar_uid(),not session_locked or network.role=="host",session_paused)

func _on_shared_state(state: Dictionary) -> void:
    var remote_scenarios: Variant = state.get("scenarios",[])
    if not (remote_scenarios is Array) or remote_scenarios.is_empty():
        return
    is_loading = true
    scenario_store = remote_scenarios.duplicate(true)
    active_index = clampi(int(state.get("active_index",0)),0,scenario_store.size()-1)
    room_revision = int(state.get("revision",1))
    session_paused = bool(state.get("paused",false))
    session_locked = bool(state.get("locked",false))
    room_players = state.get("participants",[])
    _refresh_scenarios()
    var current: Dictionary = scenario_store[active_index]
    scenario_name_field.text = str(current.get("name","Scénario"))
    note_box.text = str(current.get("notes",""))
    _render_room_objects(current.get("objects",[]))
    _update_participants()
    pause_control.text = "Reprendre la simulation" if session_paused else "Mettre en pause"
    lock_control.text = "Déverrouiller l'aménagement" if session_locked else "Verrouiller l'aménagement"
    is_loading = false
    _update_analysis()

func _update_participants() -> void:
    var result := "AGENTS DE LA SALLE (%d)\n" % room_players.size()
    for p in room_players:
        result += ("● " if bool(p.get("connected",false)) else "○ ") + str(p.get("nickname","Agent"))
        if str(p.get("role","")) == "host":
            result += " (animateur)"
        result += "\n"
    participants_label.text = result

func _on_shared_event(packet: Dictionary) -> void:
    var kind: String = str(packet.get("kind",""))
    var payload: Dictionary = packet.get("payload",{})
    if kind == "layout":
        _on_shared_state({"scenarios":payload.get("scenarios",scenario_store),"active_index":payload.get("active_index",active_index),
            "revision":payload.get("revision",room_revision),"participants":room_players,"paused":session_paused,"locked":session_locked})
    elif kind == "move":
        var id: String = str(payload.get("id",""))
        for p in room_players:
            if str(p.get("id",""))==id:
                var av: Dictionary = p.get("avatar",{})
                av["x"] = float(payload.get("x",av.get("x",980)))
                av["y"] = float(payload.get("y",av.get("y",440)))
                av["trail"] = payload.get("trail",av.get("trail",[]))
                p["avatar"] = av
                canvas.update_live_avatar(_player_uid(p),float(av["x"]),float(av["y"]),"",av.get("trail",[]))
                break
        var pushed: Variant = payload.get("pushed",null)
        if pushed is Dictionary:
            room_revision = maxi(room_revision,int(pushed.get("revision",room_revision)))
            var sc: Dictionary = scenario_store[active_index]
            for o in sc.get("objects",[]):
                if int(o.get("uid",-1)) == int(pushed.get("uid",-2)):
                    o["x"] = float(pushed.get("x",o["x"]))
                    o["y"] = float(pushed.get("y",o["y"]))
            scenario_store[active_index] = sc
            canvas.update_equipment_position(int(pushed.get("uid",-2)),float(pushed.get("x",0)),float(pushed.get("y",0)))
        _update_analysis()
    elif kind == "interaction":
        for p in room_players:
            if str(p.get("id","")) == str(payload.get("id","")):
                var av: Dictionary = p.get("avatar",{})
                av["action"] = str(payload.get("action","libre"))
                p["avatar"] = av
                canvas.set_live_action(_player_uid(p),str(av["action"]))
                break
        _set_status("Action : " + str(payload.get("action","")))
    elif kind == "presence":
        var pnew: Variant = payload.get("participant",null)
        if pnew is Dictionary:
            var found := false
            for i in range(room_players.size()):
                if str(room_players[i].get("id","")) == str(pnew.get("id","")):
                    room_players[i] = pnew
                    found = true
                    break
            if not found:
                room_players.append(pnew)
        else:
            for p in room_players:
                if str(p.get("id","")) == str(payload.get("id","")):
                    p["connected"] = bool(payload.get("connected",false))
        _render_room_objects(scenario_store[active_index].get("objects",[]))
        _update_participants()
    elif kind == "pause":
        session_paused = bool(payload.get("value",false))
        canvas.room_paused = session_paused
        pause_control.text = "Reprendre la simulation" if session_paused else "Mettre en pause"
        _set_status("Simulation en pause" if session_paused else "Simulation reprise")
    elif kind == "lock":
        session_locked = bool(payload.get("value",false))
        canvas.may_edit_equipment = not session_locked or network.role=="host"
        lock_control.text = "Déverrouiller l'aménagement" if session_locked else "Verrouiller l'aménagement"

func _on_avatar_motion(x: float, y: float) -> void:
    if network.has_room():
        network.send_move(x,y)

func _do_avatar_action() -> void:
    if not network.has_room():
        _set_status("Rejoins d'abord une salle pour jouer ton agent")
        return
    if session_paused:
        _set_status("La simulation est en pause")
        return
    var action: String = ROOM_ACTIONS[action_picker.selected]
    network.send_interaction(action,canvas.nearest_equipment_uid())

func _toggle_pause() -> void:
    if network.role == "host":
        network.send_pause(not session_paused)

func _toggle_lock() -> void:
    if network.role == "host":
        network.send_lock(not session_locked)
