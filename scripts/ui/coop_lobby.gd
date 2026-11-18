class_name CoopLobby
extends Control
## NET1: the co-op lobby, opened from the main menu (made in code, no scene file).
##
## Host: lists who has joined; only the host has Start. Join: an address box first
## ("127.0.0.1" = this same computer), then the same list while waiting for the host.

signal closed

var _title: Label
var _address_row: HBoxContainer
var _address: LineEdit
var _connect_button: Button
var _list: Label
var _status: Label
var _start_button: Button
var _back_button: Button
var _hosting: bool = false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_address_row = HBoxContainer.new()
	box.add_child(_address_row)
	var address_label := Label.new()
	address_label.text = "Host address"
	_address_row.add_child(address_label)
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text_submitted.connect(func(_t: String) -> void: _on_connect())
	_address_row.add_child(_address)
	_connect_button = Button.new()
	_connect_button.text = "Connect"
	_connect_button.pressed.connect(_on_connect)
	_address_row.add_child(_connect_button)
	_list = Label.new()
	_list.add_theme_font_size_override("font_size", 20)
	box.add_child(_list)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_start_button = Button.new()
	_start_button.text = "Start the battle"
	_start_button.pressed.connect(_on_start)
	box.add_child(_start_button)
	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.pressed.connect(_on_back)
	box.add_child(_back_button)
	visible = false


func _ready() -> void:
	NetworkManager.lobby_changed.connect(_refresh)
	NetworkManager.joined.connect(_on_joined)
	NetworkManager.connection_lost.connect(_on_connection_lost)


## Host: open the port and wait for others.
func open_host() -> void:
	_hosting = true
	visible = true
	_title.text = "Host Co-op"
	_address_row.visible = false
	var err: Error = NetworkManager.host_coop()
	if err != OK:
		_status.text = "Could not open port %d (error %d). Is another copy already hosting?" % [NetworkManager.DEFAULT_PORT, err]
		_start_button.visible = false
	else:
		_status.text = "Waiting for others to join – they connect to this computer's address (on this PC: 127.0.0.1), port %d." % NetworkManager.DEFAULT_PORT
		_start_button.visible = true
	_refresh()
	if _start_button.visible:
		_start_button.grab_focus()
	else:
		_back_button.grab_focus()


## Join: ask for the host's address first.
func open_join(address: String = "") -> void:
	_hosting = false
	visible = true
	_title.text = "Join Co-op"
	_address_row.visible = true
	_start_button.visible = false
	_connect_button.disabled = false
	if address != "":
		_address.text = address
	_status.text = "Type the host's address (on this PC: 127.0.0.1) and press Connect."
	_list.text = ""
	_address.grab_focus()


func _on_connect() -> void:
	var err: Error = NetworkManager.join_coop(_address.text)
	if err != OK:
		_status.text = "Could not connect (error %d)." % err
		return
	_connect_button.disabled = true
	_status.text = "Connecting to %s ..." % _address.text


func _on_joined() -> void:
	if not visible:
		return
	_address_row.visible = false
	_status.text = "Connected. Waiting for the host to start the battle."
	_back_button.grab_focus()


func _on_connection_lost(text: String) -> void:
	if not visible:
		return
	_connect_button.disabled = false
	_address_row.visible = not _hosting
	_list.text = ""
	_status.text = text


func _refresh() -> void:
	if not visible:
		return
	var lines: PackedStringArray = []
	var me: int = multiplayer.get_unique_id()
	for i in NetworkManager.lobby_peers.size():
		var id: int = NetworkManager.lobby_peers[i]
		var line: String = "Soldier %d" % (i + 1)
		if id == 1:
			line += " (host)"
		if id == me:
			line += " – you"
		lines.append(line)
	_list.text = "\n".join(lines)
	if _hosting:
		_start_button.disabled = NetworkManager.lobby_peers.size() < 2
		_start_button.text = "Start the battle" if not _start_button.disabled else "Start the battle (waiting for a second soldier)"


func _on_start() -> void:
	NetworkManager.begin_battle()


func _on_back() -> void:
	NetworkManager.close_connection()
	visible = false
	closed.emit()
