import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_service_example/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';

late AudioHandler _audioHandler;

Future<void> main() async {
  _audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ryanheise.myapp.channel.audio',
      androidNotificationChannelName: 'Audio Player',
      androidNotificationOngoing: true,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prova',
      theme: ThemeData.dark(),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Player'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Mostra la GIF
            Image.asset(
                'assets/music/song1.gif'), // Mostra la GIF come immagine statica

            // Mostra il titolo dell'elemento in riproduzione
            StreamBuilder<MediaItem?>(
              stream: _audioHandler.mediaItem,
              builder: (context, snapshot) {
                final mediaItem = snapshot.data;
                return Text(mediaItem?.title ?? ' ');
              },
            ),
            // Pulsanti play/pause/stop
            StreamBuilder<bool>(
              stream: _audioHandler.playbackState
                  .map((state) => state.playing)
                  .distinct(),
              builder: (context, snapshot) {
                final playing = snapshot.data ?? false;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed: () {
                        if (playing) {
                          _audioHandler.pause();
                        } else {
                          _audioHandler.play();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.stop),
                      onPressed: () => _audioHandler.stop(),
                    ),
                  ],
                );
              },
            ),
            // Barra di avanzamento (seek bar)
            StreamBuilder<MediaState>(
              stream: _mediaStateStream,
              builder: (context, snapshot) {
                final mediaState = snapshot.data;
                final duration =
                    mediaState?.mediaItem?.duration ?? Duration.zero;
                final position = mediaState?.position ?? Duration.zero;

                return Column(
                  children: [
                    SeekBar(
                      duration: duration,
                      position: position,
                      onChangeEnd: (newPosition) {
                        _audioHandler.seek(newPosition);
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${_formatDuration(position)} / ${_formatDuration(duration)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            // Stato di elaborazione
            StreamBuilder<AudioProcessingState>(
              stream: _audioHandler.playbackState
                  .map((state) => state.processingState)
                  .distinct(),
              builder: (context, snapshot) {
                final processingState =
                    snapshot.data ?? AudioProcessingState.idle;
                return Text(
                    "Processing state: ${describeEnum(processingState)}");
              },
            ),
          ],
        ),
      ),
    );
  }

  // Stream per la durata e la posizione
  Stream<MediaState> get _mediaStateStream =>
      Rx.combineLatest2<MediaItem?, Duration, MediaState>(
          _audioHandler.mediaItem,
          AudioService.position,
          (mediaItem, position) => MediaState(mediaItem, position));

  // Funzione per formattare la durata in MM:SS
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class MediaState {
  final MediaItem? mediaItem;
  final Duration position;

  MediaState(this.mediaItem, this.position);
}

class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  late final MediaItem _item;
  final _player = AudioPlayer();

  AudioPlayerHandler() {
    _initialize();
  }

  Future<void> _initialize() async {
    final artUri =
        await _getGifUriFromAsset('assets/music/song1.gif', 'song1.gif');

    // Carica l'audio e ottieni la durata effettiva
    await _player.setAudioSource(AudioSource.asset('assets/music/song1.mp3'));

    final duration =
        _player.duration ?? Duration.zero; // Ottieni la durata dal lettore

    _item = MediaItem(
      id: 'assets/music/song1.mp3',
      album: "SONGIG",
      title: "R.I.P. Sburrify",
      artist: "SonoNessunk feat. StoCazzo",
      duration: duration, // Usa la durata dinamica qui
      artUri: artUri,
    );

    // Set media item
    mediaItem.add(_item);

    // Map playback events to playback state
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  // Funzione per ottenere la URI della GIF
  Future<Uri> _getGifUriFromAsset(String assetPath, String fileName) async {
    final byteData = await rootBundle.load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file.uri;
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();

  // Trasforma gli eventi in stato di riproduzione
  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.rewind,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
