import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../data/models.dart';

/// Set once in main(); the player notifier wires its controls into it.
RoxyAudioHandler? audioHandler;

/// Notification / lock screen / Bluetooth controls: previous, play/pause, next and close.
class RoxyAudioHandler extends BaseAudioHandler with SeekHandler {
  VoidCallback? onPlay, onPause, onNext, onPrev, onStop;
  void Function(Duration)? onSeek;

  @override
  Future<void> play() async => onPlay?.call();
  @override
  Future<void> pause() async => onPause?.call();
  @override
  Future<void> skipToNext() async => onNext?.call();
  @override
  Future<void> skipToPrevious() async => onPrev?.call();
  @override
  Future<void> seek(Duration position) async => onSeek?.call(position);
  @override
  Future<void> stop() async {
    onStop?.call();
    await super.stop();
  }

  /// Hide the notification without triggering [onStop].
  Future<void> hide() => super.stop();

  void show(Song s, Duration duration) {
    mediaItem.add(MediaItem(
      id: s.id,
      title: s.title,
      artist: s.artistName,
      duration: duration > Duration.zero ? duration : null,
      artUri: s.artwork.isEmpty ? null : Uri.parse(s.artwork.replaceFirst(RegExp(r'=(w\d+-h\d+|s\d+)'), '=w544-h544')),
    ));
  }

  void sync({required bool playing, required bool loading, required Duration position}) {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        const MediaControl(androidIcon: 'drawable/ic_close', label: 'Close', action: MediaAction.stop),
      ],
      systemActions: const {MediaAction.seek, MediaAction.playPause, MediaAction.skipToNext, MediaAction.skipToPrevious},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: loading ? AudioProcessingState.loading : AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      bufferedPosition: position,
      speed: 1.0,
    ));
  }
}
