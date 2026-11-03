extends Node

signal voice_frame(payload: String)

const SAMPLE_RATE := 16000
const CAPTURE_INTERVAL := 0.05
const VAD_THRESHOLD := 0.018
const VOICE_DISTANCE := 28.0
const REMOTE_TIMEOUT := 0.45

var enabled := false
var microphone_player: AudioStreamPlayer
var capture_effect: AudioEffectCapture
var capture_bus := -1
var elapsed := 0.0
var listener_position := Vector3.ZERO
var remote_players: Dictionary = {}
var remote_last_frame: Dictionary = {}

func request_microphone_permission() -> bool:
    if not OS.has_feature("android"):
        return true
    var permission := "android.permission.RECORD_AUDIO"
    var permission_granted := false
    if OS.has_method("get_granted_permissions"):
        for attempt in range(40):
            permission_granted = permission in OS.get_granted_permissions()
            if permission_granted:
                break
            if attempt == 0:
                OS.request_permission(permission)
            await get_tree().create_timer(0.25).timeout
    else:
        permission_granted = OS.request_permission(permission)
        await get_tree().create_timer(0.75).timeout
    return permission_granted

func start() -> void:
    if enabled:
        return
    if not await request_microphone_permission():
        push_warning("VoiceChat: permissão do microfone não concedida")
        return
    capture_bus = AudioServer.get_bus_index("VoiceCapture")
    if capture_bus < 0:
        AudioServer.add_bus()
        capture_bus = AudioServer.bus_count - 1
        AudioServer.set_bus_name(capture_bus, "VoiceCapture")
    if capture_effect == null:
        capture_effect = AudioEffectCapture.new()
        capture_effect.buffer_length = 0.25
        AudioServer.add_bus_effect(capture_bus, capture_effect, 0)
    else:
        capture_effect.clear_buffer()
    AudioServer.set_bus_volume_db(capture_bus, -80.0)
    microphone_player = AudioStreamPlayer.new()
    microphone_player.stream = AudioStreamMicrophone.new()
    microphone_player.bus = "VoiceCapture"
    add_child(microphone_player)
    microphone_player.play()
    enabled = true

func stop_microphone() -> void:
    enabled = false
    if microphone_player != null:
        microphone_player.stop()
        microphone_player.queue_free()
        microphone_player = null
    if capture_effect != null:
        capture_effect.clear_buffer()

func stop() -> void:
    stop_microphone()
    for player in remote_players.values():
        if is_instance_valid(player):
            player.queue_free()
    remote_players.clear()
    remote_last_frame.clear()

func set_listener_position(position: Vector3) -> void:
    listener_position = position

func _process(delta: float) -> void:
    var now := Time.get_ticks_msec() / 1000.0
    for remote_id in remote_last_frame.keys():
        if now - float(remote_last_frame[remote_id]) > REMOTE_TIMEOUT:
            var player: AudioStreamPlayer = remote_players.get(remote_id)
            if player != null:
                player.volume_db = -80.0
    if not enabled or capture_effect == null:
        return
    elapsed += delta
    if elapsed >= CAPTURE_INTERVAL:
        elapsed = fmod(elapsed, CAPTURE_INTERVAL)
        _capture_and_emit()

func _capture_and_emit() -> void:
    var available := capture_effect.get_frames_available()
    if available < 720:
        return
    var frames := capture_effect.get_buffer(mini(available, 1323))
    if frames.is_empty():
        return
    var samples: PackedInt32Array = []
    var energy := 0.0
    var count := 0
    for index in range(0, frames.size(), 3):
        var frame: Vector2 = frames[index]
        var sample := clampf((frame.x + frame.y) * 0.5, -1.0, 1.0)
        energy += sample * sample
        samples.append(int(round(sample * 32767.0)))
        count += 1
        if count >= 441:
            break
    if samples.is_empty():
        return
    var rms := sqrt(energy / float(samples.size()))
    if rms < VAD_THRESHOLD:
        return
    var bytes := PackedByteArray()
    bytes.resize(samples.size() * 2)
    for index in samples.size():
        bytes.encode_s16(index * 2, samples[index])
    voice_frame.emit(Marshalls.raw_to_base64(bytes))

func play_remote_voice(remote_id: String, encoded: String, remote_position: Vector3) -> void:
    if remote_id.is_empty() or encoded.is_empty():
        return
    var distance := listener_position.distance_to(remote_position)
    if distance > VOICE_DISTANCE:
        return
    var bytes: PackedByteArray = Marshalls.base64_to_raw(encoded)
    if bytes.is_empty() or bytes.size() > 1200:
        return
    var player: AudioStreamPlayer = remote_players.get(remote_id)
    if player == null:
        var stream := AudioStreamGenerator.new()
        stream.mix_rate = SAMPLE_RATE
        stream.buffer_length = 0.35
        player = AudioStreamPlayer.new()
        player.stream = stream
        player.bus = "Master"
        add_child(player)
        player.play()
        remote_players[remote_id] = player
    var gain := clampf(1.0 - distance / VOICE_DISTANCE, 0.08, 1.0)
    player.volume_db = linear_to_db(gain)
    var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
    if playback == null:
        return
    for index in range(0, bytes.size() - 1, 2):
        var sample := float(bytes.decode_s16(index)) / 32768.0
        playback.push_frame(Vector2(sample, sample))
    remote_last_frame[remote_id] = Time.get_ticks_msec() / 1000.0

func remove_remote(remote_id: String) -> void:
    var player: AudioStreamPlayer = remote_players.get(remote_id)
    if player != null:
        player.queue_free()
    remote_players.erase(remote_id)
    remote_last_frame.erase(remote_id)
