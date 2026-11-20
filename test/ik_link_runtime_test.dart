import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/share/deep_link_service.dart';
import 'package:mconnect/core/share/share_links.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ik/ik_link_runtime.dart';

import 'support/content_page_fakes.dart';

class _Source implements LinkSource {
  final initial = Completer<Uri?>();
  final stream = StreamController<Uri>.broadcast();
  int subscriptions = 0;
  @override
  Future<Uri?> initialLink() => initial.future;
  @override
  Stream<Uri> links() {
    subscriptions++;
    return stream.stream;
  }
}

class _Player extends PlayerNotifier {
  _Player() : super(audioController: IdleAudioController());
  final songs = <Song>[];
  @override
  Future<void> playSong(Song song, {bool startPlaying = true}) async {
    songs.add(song);
  }
}

void main() {
  test('K06 关闭期间返回的初始链接不能订阅或执行', () async {
    final source = _Source();
    addTearDown(source.stream.close);
    final links = <Uri>[];
    final runtime = IkLinkController(
      source: source,
      onLink: (uri) async {
        links.add(uri);
      },
    );
    final starting = runtime.start();
    await runtime.dispose();
    source.initial.complete(Uri.parse('mconnect://song?platform=qq&id=old'));
    await starting;
    expect(links, isEmpty);
    expect(source.subscriptions, 0);
  });

  test('K06 不可用的链接插件不使启动失败', () async {
    final source = _Source();
    addTearDown(source.stream.close);
    final runtime = IkLinkController(source: source, onLink: (_) async {});
    final starting = runtime.start();
    source.initial.completeError(MissingPluginException());
    await starting;
    await runtime.dispose();
  });

  testWidgets('K06 初始和运行链接使用当前播放器与独立导航，初始重放去重', (tester) async {
    final source = _Source();
    addTearDown(source.stream.close);
    final player = _Player();
    final routes = <String>[];
    const song = Song(
      id: 'first',
      name: '分享歌曲',
      platform: PlatformType.qq,
      artists: [],
    );
    final first = Uri.parse(ShareLinks.songLink(song));
    source.initial.complete(first);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWith((ref) => player)],
        child: MaterialApp(
          home: IkLinkRuntime(
            source: source,
            onNavigate: routes.add,
            child: const Scaffold(body: Text('ik')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(player.songs.map((s) => s.id), ['first']);
    expect(routes, ['/player']);
    source.stream.add(first);
    await tester.pumpAndSettle();
    expect(player.songs, hasLength(1));
    source.stream.add(Uri.parse('mconnect://song?platform=qq&id=second'));
    await tester.pumpAndSettle();
    expect(player.songs.map((s) => s.id), ['first', 'second']);
    await tester.pumpWidget(const SizedBox());
    source.stream.add(Uri.parse('mconnect://song?platform=qq&id=disposed'));
    await tester.pumpAndSettle();
    expect(player.songs, hasLength(2));
  });
}
