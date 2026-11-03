from pathlib import Path
import unittest


GAME_ROOT = Path(__file__).resolve().parents[1]


class MicrophoneHudToggleTests(unittest.TestCase):
    def test_microphone_is_off_until_the_hud_button_is_used(self):
        voice_chat = (GAME_ROOT / "autoload" / "voice_chat.gd").read_text(encoding="utf-8")
        self.assertIn("var enabled := false", voice_chat)

        multiplayer = (GAME_ROOT / "scripts" / "net" / "multiplayer_client.gd").read_text(encoding="utf-8")
        ready_start = multiplayer.index("func _ready() -> void:")
        ready_end = multiplayer.index("\nfunc _exit_tree()", ready_start)
        self.assertNotIn("VoiceChat.start()", multiplayer[ready_start:ready_end])
        self.assertIn("VoiceChat.voice_frame.connect(_on_voice_frame)", multiplayer)

        menu = (GAME_ROOT / "scripts" / "session_menu.gd").read_text(encoding="utf-8")
        start_game = menu.index("func _start_game() -> void:")
        load_screen = menu.index("func _show_loading_screen()", start_game)
        self.assertNotIn("request_microphone_permission", menu[start_game:load_screen])

        gameplay = (GAME_ROOT / "scripts" / "third_person.gd").read_text(encoding="utf-8")
        self.assertIn('microphone_button.toggled.connect(_on_microphone_button_toggled)', gameplay)
        self.assertIn("await VoiceChat.start()", gameplay)
        self.assertIn("VoiceChat.stop_microphone()", gameplay)
        self.assertIn('"hud.microphone": hud_root.get_node_or_null("MicButton")', gameplay)
        self.assertIn('[node name="MicButton" type="Button" parent="HUD/Root"]', (GAME_ROOT / "scenes" / "third_person.tscn").read_text(encoding="utf-8"))

    def test_disabling_the_mic_preserves_remote_voice_playback(self):
        voice_chat = (GAME_ROOT / "autoload" / "voice_chat.gd").read_text(encoding="utf-8")
        start = voice_chat.index("func stop_microphone() -> void:")
        end = voice_chat.index("\nfunc stop() -> void:", start)
        stop_microphone = voice_chat[start:end]
        self.assertIn("microphone_player.stop()", stop_microphone)
        self.assertIn("capture_effect.clear_buffer()", stop_microphone)
        self.assertNotIn("remote_players.clear()", stop_microphone)


if __name__ == "__main__":
    unittest.main()
