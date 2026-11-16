import '../../l10n/expanded_strings.dart';

import 'package:flutter/material.dart';

import '../../models/playlist.dart';
import '../../models/song.dart';
import '../data/video_catalog.dart';
import '../data/video_kugou_catalog.dart';

class VideoKugouPlaylistsPage extends StatefulWidget {
  const VideoKugouPlaylistsPage({
    super.key,
    required this.loadPlaylists,
    required this.loadSongs,
    required this.isSessionCurrent,
    required this.onPlay,
    required this.onDownload,
  });
  final Future<VideoKugouPlaylists> Function() loadPlaylists;
  final Future<VideoLibrary> Function(Playlist) loadSongs;
  final bool Function() isSessionCurrent;
  final void Function(Song, List<Song>) onPlay;
  final ValueChanged<List<Song>> onDownload;
  @override
  State<VideoKugouPlaylistsPage> createState() =>
      _VideoKugouPlaylistsPageState();
}

class _VideoKugouPlaylistsPageState extends State<VideoKugouPlaylistsPage> {
  VideoKugouPlaylists _playlists = const VideoKugouPlaylists();
  VideoLibrary _songs = const VideoLibrary();
  Playlist? _selected;
  bool _loading = true;
  int _generation = 0;
  String? _sessionError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _current() {
    if (widget.isSessionCurrent()) return true;
    setState(() {
      _sessionError = ExpandedStrings.sessionChanged;
      _songs = const VideoLibrary();
      _playlists = const VideoKugouPlaylists();
      _loading = false;
    });
    return false;
  }

  Future<void> _load() async {
    if (!_current()) return;
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      if (_selected == null) {
        final value = await widget.loadPlaylists();
        if (!mounted || generation != _generation || !_current()) return;
        setState(() => _playlists = value);
      } else {
        final value = await widget.loadSongs(_selected!);
        if (!mounted || generation != _generation || !_current()) return;
        setState(() => _songs = value);
      }
    } catch (error) {
      if (!mounted || generation != _generation || !_current()) return;
      setState(() {
        final failure = VideoFailure.from(error);
        if (_selected == null) {
          _playlists = VideoKugouPlaylists(error: failure);
        } else {
          _songs = VideoLibrary(error: failure);
        }
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _backToList() {
    _generation++;
    setState(() {
      _selected = null;
      _songs = const VideoLibrary();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final failure = _selected == null ? _playlists.error : _songs.error;
    final count = _selected == null ? _playlists.items.length : _songs.loaded;
    final complete = _selected == null ? _playlists.complete : _songs.complete;
    final message = _sessionError ?? failure?.message;
    return PopScope(
      canPop: _selected == null,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) _backToList();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_selected?.name ?? ExpandedStrings.kugouPlaylists),
          leading: _selected == null
              ? null
              : BackButton(onPressed: _backToList),
          actions: [
            IconButton(
              tooltip: ExpandedStrings.refreshPlaylists,
              onPressed: _loading || _sessionError != null ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(message),
                ),
              if (failure?.canRetry == true &&
                  !_loading &&
                  _sessionError == null)
                TextButton(
                  onPressed: _load,
                  child: const Text(ExpandedStrings.retry),
                ),
              if (_sessionError == null && !_loading)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(ExpandedStrings.loadedCount(count, complete)),
                ),
              if (_selected != null && _songs.songs.isNotEmpty)
                Wrap(
                  spacing: 16,
                  children: [
                    FilledButton.icon(
                      onPressed: _loading
                          ? null
                          : () {
                              if (_current()) {
                                widget.onPlay(_songs.songs.first, _songs.songs);
                              }
                            },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text(ExpandedStrings.playLoaded),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              if (_current()) widget.onDownload(_songs.songs);
                            },
                      child: const Text(ExpandedStrings.downloadLoaded),
                    ),
                  ],
                ),
              Expanded(
                child: _selected == null
                    ? ListView.builder(
                        itemCount: _playlists.items.length,
                        itemBuilder: (_, index) {
                          final playlist = _playlists.items[index];
                          return ListTile(
                            leading: const Icon(Icons.queue_music),
                            title: Text(playlist.name),
                            subtitle: Text(
                              ExpandedStrings.songCount(playlist.songCount),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _loading
                                ? null
                                : () {
                                    if (!_current()) return;
                                    setState(() => _selected = playlist);
                                    _load();
                                  },
                          );
                        },
                      )
                    : ListView.builder(
                        itemCount: _songs.songs.length,
                        itemBuilder: (_, index) {
                          final song = _songs.songs[index];
                          return ListTile(
                            title: Text(song.name),
                            subtitle: Text(song.artistNames),
                            trailing: const Icon(Icons.play_arrow),
                            onTap: _loading
                                ? null
                                : () {
                                    if (_current()) {
                                      widget.onPlay(song, _songs.songs);
                                    }
                                  },
                          );
                        },
                      ),
              ),
              if (!_loading && count == 0 && message == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(ExpandedStrings.empty),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
