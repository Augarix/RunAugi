import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class AudioService {
  AudioService._();
  static final instance = AudioService._();

  final _player = AudioPlayer();

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  Future<void> playMenu() async {
    try {
      await _player.setAsset('assets/music/menu.mp3');
      _player.setLoopMode(LoopMode.one);
      await _player.play();
    } catch (_) {}
  }

  Future<void> stop() async => _player.stop();
}
