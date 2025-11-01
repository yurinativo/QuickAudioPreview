@tool
extends EditorPlugin

var _player: AudioStreamPlayer
var _fs_tree: Tree

func _enter_tree():
	_player = AudioStreamPlayer.new()
	add_child(_player)

	var fsdock := get_editor_interface().get_file_system_dock()
	_fs_tree = _find_tree(fsdock)
	if _fs_tree:
		_fs_tree.connect("cell_selected", Callable(self, "_on_cell_selected"))
		_fs_tree.connect("item_activated", Callable(self, "_on_item_activated"))

func _exit_tree():
	if is_instance_valid(_fs_tree):
		if _fs_tree.is_connected("cell_selected", Callable(self, "_on_cell_selected")):
			_fs_tree.disconnect("cell_selected", Callable(self, "_on_cell_selected"))
		if _fs_tree.is_connected("item_activated", Callable(self, "_on_item_activated")):
			_fs_tree.disconnect("item_activated", Callable(self, "_on_item_activated"))
	if is_instance_valid(_player):
		_player.queue_free()

func _find_tree(n: Node) -> Tree:
	if n is Tree:
		print(n.name)
		return n
	for c in n.get_children():
		var t := _find_tree(c)
		if t:
			return t
	return null

func _on_cell_selected(_arg = null):
	play()
	
func _on_item_activated(_arg = null):
	play()
	
func print_selected():
	
	var selection: EditorSelection = get_editor_interface().get_selection()
	for node in selection.get_selected_nodes():
		print(node.name)
	
func play():
		
	var paths: PackedStringArray = get_editor_interface().get_selected_paths()
	if paths.is_empty():
		return
		
	var path := paths[0]  # last selected
	var ext := path.get_extension().to_lower()
	
	if ext in ["wav", "ogg", "mp3", "flac"]:
		var stream: AudioStream = load(path)
		if stream:
			_player.stop()
			_player.stream = stream
			_player.play()
