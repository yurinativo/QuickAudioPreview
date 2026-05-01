@tool
extends EditorPlugin


class WaveformDisplay extends Control:
	var _mins: PackedFloat32Array
	var _maxes: PackedFloat32Array
	var _playhead: float = 0.0

	func set_waveform(mins: PackedFloat32Array, maxes: PackedFloat32Array) -> void:
		_mins = mins
		_maxes = maxes
		queue_redraw()

	func clear_waveform() -> void:
		_mins = PackedFloat32Array()
		_maxes = PackedFloat32Array()
		queue_redraw()

	func set_playhead(t: float) -> void:
		_playhead = t
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.08, 0.08))
		var bins := _mins.size()
		if bins > 0 and w > 0.0:
			for x in int(w):
				var bin := clamp(int(float(x) / w * bins), 0, bins - 1)
				var lo := _mins[bin] * 0.5 + 0.5
				var hi := _maxes[bin] * 0.5 + 0.5
				var amp := hi - lo
				var color: Color
				if amp < 0.5:
					color = Color(0.2, 0.85, 0.2).lerp(Color(0.95, 0.85, 0.1), amp * 2.0)
				else:
					color = Color(0.95, 0.85, 0.1).lerp(Color(0.95, 0.15, 0.1), (amp - 0.5) * 2.0)
				draw_line(Vector2(x, lo * h), Vector2(x, hi * h), color, 1.0)
		draw_line(Vector2(_playhead * w, 0.0), Vector2(_playhead * w, h), Color(1.0, 1.0, 1.0, 0.85), 1.5)


var _player: AudioStreamPlayer
var _fs_trees: Array[Tree] = []
var _current_path: String = ""
var _paused_position: float = 0.0
var _is_paused: bool = false
var _seeking: bool = false

var _panel: VBoxContainer
var _play_btn: Button
var _name_label: Label
var _time_label: Label
var _waveform: WaveformDisplay
var _slider: HSlider

var _waveform_thread: Thread = null
var _waveform_gen: int = 0
var _finished_threads: Array = []

var _icon_play: Texture2D
var _icon_pause: Texture2D


func _enter_tree() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_on_finished)
	set_process(true)

	var fsdock := get_editor_interface().get_file_system_dock()
	_find_all_trees(fsdock, _fs_trees)
	for tree in _fs_trees:
		tree.item_mouse_selected.connect(_on_item_mouse_selected)

	_build_panel()
	add_control_to_bottom_panel(_panel, "Audio Preview")
	_load_icons()


func _exit_tree() -> void:
	set_process(false)
	_waveform_gen += 1
	if _waveform_thread != null and _waveform_thread.is_started():
		_waveform_thread.wait_to_finish()
	for t in _finished_threads:
		if t.is_started():
			t.wait_to_finish()
	_finished_threads.clear()
	for tree in _fs_trees:
		if is_instance_valid(tree) and tree.item_mouse_selected.is_connected(_on_item_mouse_selected):
			tree.item_mouse_selected.disconnect(_on_item_mouse_selected)
	_fs_trees.clear()
	if is_instance_valid(_player):
		_player.queue_free()
	if is_instance_valid(_panel):
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()


func _process(_delta: float) -> void:
	for t in _finished_threads.duplicate():
		if not t.is_alive():
			t.wait_to_finish()
			_finished_threads.erase(t)

	if not is_instance_valid(_player) or _player.stream == null:
		return
	var length := _player.stream.get_length()
	if length <= 0.0:
		return
	var pos := _player.get_playback_position() if _player.playing else _paused_position
	if not _seeking:
		_slider.set_value_no_signal(pos / length)
		_waveform.set_playhead(pos / length)
	_time_label.text = "%s / %s" % [_fmt(pos), _fmt(length)]


func _fmt(s: float) -> String:
	var t := int(s)
	return "%d:%02d" % [t / 60, t % 60]


func _load_icons() -> void:
	var base := get_editor_interface().get_base_control()
	_icon_play = base.get_theme_icon("MainPlay", "EditorIcons")
	_icon_pause = base.get_theme_icon("Pause", "EditorIcons")
	_play_btn.icon = _icon_play


func _build_panel() -> void:
	_panel = VBoxContainer.new()
	_panel.custom_minimum_size.y = 90

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	_panel.add_child(controls)

	_play_btn = Button.new()
	_play_btn.disabled = true
	_play_btn.custom_minimum_size.x = 32
	_play_btn.pressed.connect(_toggle_playback)
	controls.add_child(_play_btn)

	_name_label = Label.new()
	_name_label.text = "No file selected"
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	controls.add_child(_name_label)

	_time_label = Label.new()
	_time_label.text = "0:00 / 0:00"
	controls.add_child(_time_label)

	_waveform = WaveformDisplay.new()
	_waveform.custom_minimum_size = Vector2(0, 52)
	_waveform.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(_waveform)

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.0
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.drag_started.connect(func(): _seeking = true)
	_slider.drag_ended.connect(_on_seek_ended)
	_panel.add_child(_slider)


func _on_seek_ended(changed: bool) -> void:
	_seeking = false
	if not changed or _player.stream == null:
		return
	var pos := _slider.value * _player.stream.get_length()
	if _player.playing:
		_player.seek(pos)
	else:
		_paused_position = pos
		_waveform.set_playhead(_slider.value)


func _find_all_trees(n: Node, result: Array[Tree]) -> void:
	if n is Tree:
		result.append(n)
	for c in n.get_children():
		_find_all_trees(c, result)


func _on_item_mouse_selected(_pos: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	call_deferred("_handle_selection")


func _handle_selection() -> void:
	var paths := get_editor_interface().get_selected_paths()
	if paths.is_empty():
		return
	var path := paths[0]
	if not path.get_extension().to_lower() in ["wav", "ogg", "mp3", "flac"]:
		return
	if _current_path == path:
		_toggle_playback()
	else:
		_load_and_play(path)


func _load_and_play(path: String) -> void:
	var stream: AudioStream = load(path)
	if not stream:
		return
	_current_path = path
	_is_paused = false
	_paused_position = 0.0
	_player.stream = stream
	_player.play()
	_play_btn.disabled = false
	_play_btn.icon = _icon_pause
	_name_label.text = path.get_file()
	_slider.set_value_no_signal(0.0)
	_waveform.set_playhead(0.0)
	_waveform.clear_waveform()
	_request_waveform(path, stream)


func _request_waveform(path: String, stream: AudioStream) -> void:
	_waveform_gen += 1
	var gen := _waveform_gen
	if _waveform_thread != null and _waveform_thread.is_started():
		_finished_threads.append(_waveform_thread)
	_waveform_thread = Thread.new()
	_waveform_thread.start(_build_waveform.bind(path, stream, gen))


func _build_waveform(path: String, stream: AudioStream, gen: int) -> void:
	const NUM_BINS := 2048
	var mins := PackedFloat32Array()
	var maxes := PackedFloat32Array()
	mins.resize(NUM_BINS)
	maxes.resize(NUM_BINS)
	for i in NUM_BINS:
		mins[i] = 0.0
		maxes[i] = 0.0

	var ok := false
	match path.get_extension().to_lower():
		"wav":
			ok = _parse_wav(path, mins, maxes, NUM_BINS, gen)
		"ogg":
			ok = _parse_ogg(stream, mins, maxes, NUM_BINS, gen)
		"mp3":
			ok = _parse_mp3(stream, mins, maxes, NUM_BINS, gen)

	if ok and gen == _waveform_gen:
		call_deferred("_apply_waveform", gen, mins, maxes)


func _parse_wav(path: String, mins: PackedFloat32Array, maxes: PackedFloat32Array, num_bins: int, gen: int) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return false

	if f.get_buffer(4).get_string_from_ascii() != "RIFF":
		return false
	f.get_32()  # file size (unused)
	if f.get_buffer(4).get_string_from_ascii() != "WAVE":
		return false

	var channels := 1
	var bits_per_sample := 16
	var audio_format := 1  # 1 = PCM

	while not f.eof_reached():
		var chunk_id := f.get_buffer(4).get_string_from_ascii()
		var chunk_size := f.get_32()

		if chunk_id == "fmt ":
			audio_format = f.get_16()
			channels = f.get_16()
			f.get_32()  # sample rate
			f.get_32()  # byte rate
			f.get_16()  # block align
			bits_per_sample = f.get_16()
			var extra := int(chunk_size) - 16
			if extra > 0:
				f.seek(f.get_position() + extra)

		elif chunk_id == "data":
			if audio_format != 1:
				return false  # Not PCM (e.g. float, ADPCM)
			if bits_per_sample != 8 and bits_per_sample != 16:
				return false

			var data := f.get_buffer(chunk_size)
			var bps := bits_per_sample / 8         # bytes per sample
			var frame_size := bps * channels
			var num_frames := chunk_size / frame_size
			if num_frames == 0:
				return false

			# Subsample so that GDScript loop stays under ~20k iterations
			# regardless of file length, while keeping ≥8 samples per bin.
			var step := max(1, num_frames / (num_bins * 8))

			var i := 0
			while i < num_frames:
				if gen != _waveform_gen:
					return false  # newer file loaded, abort

				var base := i * frame_size
				var s := 0.0
				if bits_per_sample == 8:
					# 8-bit WAV is unsigned: 0–255, silence = 128
					for c in channels:
						s += int(data[base + c]) - 128
					s /= 128.0 * channels
				else:
					# 16-bit WAV is signed little-endian
					for c in channels:
						var off := base + c * 2
						var raw := (int(data[off + 1]) << 8) | int(data[off])
						if raw > 32767:
							raw -= 65536
						s += raw
					s /= 32768.0 * channels

				var bin := clamp(i * num_bins / num_frames, 0, num_bins - 1)
				if s < mins[bin]: mins[bin] = s
				if s > maxes[bin]: maxes[bin] = s
				i += step

			return true

		else:
			f.seek(f.get_position() + chunk_size)

	return false


# Same approximation as OGG — AudioStreamMP3.data is the raw MP3 file bytes,
# not PCM. Compressed bytes correlate loosely with audio energy.
func _parse_mp3(stream: AudioStream, mins: PackedFloat32Array, maxes: PackedFloat32Array, num_bins: int, gen: int) -> bool:
	if not stream is AudioStreamMP3:
		return false
	var data: PackedByteArray = (stream as AudioStreamMP3).data
	if data.is_empty():
		return false

	var total := data.size()
	var step := max(1, total / (num_bins * 8))
	var i := 0
	while i < total:
		if gen != _waveform_gen:
			return false
		var bin := clamp(i * num_bins / total, 0, num_bins - 1)
		var s := (float(data[i]) / 128.0 - 1.0) * 0.9
		if s < mins[bin]: mins[bin] = s
		if s > maxes[bin]: maxes[bin] = s
		i += step

	return true


# Approximation: treats raw Vorbis compressed bytes as amplitude proxies.
# This is NOT real PCM — Vorbis packets are entropy-coded, so the bytes
# reflect bitstream complexity rather than true sample values. The result
# gives a rough energy envelope rather than an accurate waveform shape.
func _parse_ogg(stream: AudioStream, mins: PackedFloat32Array, maxes: PackedFloat32Array, num_bins: int, gen: int) -> bool:
	if not stream is AudioStreamOggVorbis:
		return false
	var packet_seq = (stream as AudioStreamOggVorbis).packet_sequence
	if not packet_seq:
		return false

	# packet_data is Array[Array[PackedByteArray]]: pages → packets → bytes.
	# The first 3 pages are Vorbis headers (identification, comment, setup).
	# Audio data begins at page index 3.
	var pages: Array = packet_seq.packet_data
	if pages.size() <= 3:
		return false

	var total := 0
	for pi in range(3, pages.size()):
		for pkt in pages[pi]:
			total += (pkt as PackedByteArray).size()
	if total == 0:
		return false

	var step := max(1, total / (num_bins * 8))
	var pos := 0
	var next_sample := 0

	for pi in range(3, pages.size()):
		if gen != _waveform_gen:
			return false
		for pkt in pages[pi]:
			var bytes := pkt as PackedByteArray
			for bi in bytes.size():
				if pos >= next_sample:
					var bin := clamp(pos * num_bins / total, 0, num_bins - 1)
					var s := (float(bytes[bi]) / 128.0 - 1.0) * 0.9
					if s < mins[bin]: mins[bin] = s
					if s > maxes[bin]: maxes[bin] = s
					next_sample = pos + step
				pos += 1

	return true


func _apply_waveform(gen: int, mins: PackedFloat32Array, maxes: PackedFloat32Array) -> void:
	if gen != _waveform_gen:
		return
	_waveform.set_waveform(mins, maxes)


func _toggle_playback() -> void:
	if _player.playing:
		_paused_position = _player.get_playback_position()
		_player.stop()
		_is_paused = true
		_play_btn.icon = _icon_play
	elif _player.stream:
		_player.play(_paused_position)
		_is_paused = false
		_play_btn.icon = _icon_pause


func _on_finished() -> void:
	_is_paused = false
	_paused_position = 0.0
	_play_btn.icon = _icon_play
	_slider.set_value_no_signal(0.0)
	_waveform.set_playhead(0.0)
