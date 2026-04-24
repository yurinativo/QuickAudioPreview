@tool
extends EditorPlugin

var _player: AudioStreamPlayer
var _fs_tree: Tree
var _current_path: String = ""

func _enter_tree():
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(func(): _current_path = "")

	var fsdock := get_editor_interface().get_file_system_dock()
	_fs_tree = _find_tree(fsdock)
	if _fs_tree:
		_fs_tree.item_mouse_selected.connect(_on_item_mouse_selected)

func _exit_tree():
	if is_instance_valid(_fs_tree):
		if _fs_tree.item_mouse_selected.is_connected(_on_item_mouse_selected):
			_fs_tree.item_mouse_selected.disconnect(_on_item_mouse_selected)
	if is_instance_valid(_player):
		_player.queue_free()

func _find_tree(n: Node) -> Tree:
	if n is Tree:
		return n
	for c in n.get_children():
		var t := _find_tree(c)
		if t:
			return t
	return null

func _on_item_mouse_selected(_pos: Vector2, _button: int):
	play()

func play():
	var paths: PackedStringArray = get_editor_interface().get_selected_paths()
	if paths.is_empty():
		return

	var path := paths[0]
	var ext := path.get_extension().to_lower()

	if ext in ["wav", "ogg", "mp3", "flac"]:
		if _player.playing and _current_path == path:
			_player.stop()
			_current_path = ""
			return
		var stream: AudioStream = load(path)
		if stream:
			_player.stop()
			_current_path = path
			_player.stream = stream
			_player.play()
