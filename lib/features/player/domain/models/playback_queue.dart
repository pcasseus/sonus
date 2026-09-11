import 'playback_track.dart';

class PlaybackQueue {
  const PlaybackQueue({this.tracks = const [], this.currentIndex = -1});

  final List<PlaybackTrack> tracks;
  final int currentIndex;

  bool get isEmpty => tracks.isEmpty;

  bool get isNotEmpty => tracks.isNotEmpty;

  int get length => tracks.length;

  bool get hasCurrentTrack => currentIndex >= 0 && currentIndex < tracks.length;

  PlaybackTrack? get currentTrack {
    if (!hasCurrentTrack) {
      return null;
    }

    return tracks[currentIndex];
  }

  bool get hasPrevious => hasCurrentTrack && currentIndex > 0;

  bool get hasNext => hasCurrentTrack && currentIndex < tracks.length - 1;

  PlaybackTrack? trackAt(int index) {
    if (index < 0 || index >= tracks.length) {
      return null;
    }

    return tracks[index];
  }

  PlaybackQueue replace({
    required List<PlaybackTrack> tracks,
    int startIndex = 0,
  }) {
    final immutableTracks = List<PlaybackTrack>.unmodifiable(tracks);

    if (immutableTracks.isEmpty) {
      return const PlaybackQueue();
    }

    if (startIndex < 0 || startIndex >= immutableTracks.length) {
      throw RangeError.index(startIndex, immutableTracks, 'startIndex');
    }

    return PlaybackQueue(tracks: immutableTracks, currentIndex: startIndex);
  }

  PlaybackQueue moveTo(int index) {
    if (index < 0 || index >= tracks.length) {
      throw RangeError.index(index, tracks, 'index');
    }

    return PlaybackQueue(tracks: tracks, currentIndex: index);
  }

  PlaybackQueue moveNext() {
    if (!hasNext) {
      return this;
    }

    return moveTo(currentIndex + 1);
  }

  PlaybackQueue movePrevious() {
    if (!hasPrevious) {
      return this;
    }

    return moveTo(currentIndex - 1);
  }

  PlaybackQueue insertTrack(PlaybackTrack track, {required int index}) {
    if (index < 0 || index > tracks.length) {
      throw RangeError.range(index, 0, tracks.length, 'index');
    }

    final updatedTracks = List<PlaybackTrack>.of(tracks)..insert(index, track);

    var updatedCurrentIndex = currentIndex;

    if (hasCurrentTrack && index <= currentIndex) {
      updatedCurrentIndex++;
    }

    if (!hasCurrentTrack && updatedTracks.isNotEmpty) {
      updatedCurrentIndex = 0;
    }

    return PlaybackQueue(
      tracks: List<PlaybackTrack>.unmodifiable(updatedTracks),
      currentIndex: updatedCurrentIndex,
    );
  }

  PlaybackQueue appendTrack(PlaybackTrack track) {
    return insertTrack(track, index: tracks.length);
  }

  PlaybackQueue removeTrackAt(int index) {
    if (index < 0 || index >= tracks.length) {
      throw RangeError.index(index, tracks, 'index');
    }

    final updatedTracks = List<PlaybackTrack>.of(tracks)..removeAt(index);

    if (updatedTracks.isEmpty) {
      return const PlaybackQueue();
    }

    var updatedCurrentIndex = currentIndex;

    if (index < currentIndex) {
      updatedCurrentIndex--;
    } else if (index == currentIndex) {
      if (updatedCurrentIndex >= updatedTracks.length) {
        updatedCurrentIndex = updatedTracks.length - 1;
      }
    }

    return PlaybackQueue(
      tracks: List<PlaybackTrack>.unmodifiable(updatedTracks),
      currentIndex: updatedCurrentIndex,
    );
  }

  PlaybackQueue moveTrack({required int oldIndex, required int newIndex}) {
    if (oldIndex < 0 || oldIndex >= tracks.length) {
      throw RangeError.index(oldIndex, tracks, 'oldIndex');
    }

    if (newIndex < 0 || newIndex >= tracks.length) {
      throw RangeError.index(newIndex, tracks, 'newIndex');
    }

    if (oldIndex == newIndex) {
      return this;
    }

    final updatedTracks = List<PlaybackTrack>.of(tracks);
    final movedTrack = updatedTracks.removeAt(oldIndex);
    updatedTracks.insert(newIndex, movedTrack);

    var updatedCurrentIndex = currentIndex;

    if (currentIndex == oldIndex) {
      updatedCurrentIndex = newIndex;
    } else if (oldIndex < currentIndex && newIndex >= currentIndex) {
      updatedCurrentIndex--;
    } else if (oldIndex > currentIndex && newIndex <= currentIndex) {
      updatedCurrentIndex++;
    }

    return PlaybackQueue(
      tracks: List<PlaybackTrack>.unmodifiable(updatedTracks),
      currentIndex: updatedCurrentIndex,
    );
  }
}
