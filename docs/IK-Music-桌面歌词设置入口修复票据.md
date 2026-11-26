# IK Music 桌面歌词设置入口修复票据

日期：2026-11-26。状态：用户要求继续修正，源码实施；暂停验证的指令仍有效。

## 原因与范围

用户已经看到新版桌面歌词，但找不到设置入口。六项样式设置已存在于主程序 `/settings/lyrics` 的 `refinedLyrics` 分支；缺陷是使用歌词时缺少近处、清楚的入口。本轮只补入口与导航，不新增另一套设置，不改已有偏好、播放算法或歌词样式。

这是既有功能的可发现性缺陷修复，按用户要求直接实施。桌面歌词 hover 工具栏新增齿轮，提示“桌面歌词设置”；原有上一首、播放／暂停、下一首、锁定、关闭的事件与行为保持。主播放器桌面歌词开关旁再提供同一设置入口，锁定歌词时也能从主窗调整或解锁。

## 接口与调用链

1. 新 `CompactFloatingLyricsWindow` 齿轮发送独立 `settingsRequested` 事件，不把它编码成旧 `controlRequested` 的未知 action。
2. `FloatingLyricsChannel` 新事件分支查找当前进程中带既有 `IkDesktopHost::WindowProperty()` 标记的主窗，投递已有 `WakeMessage()`。既有 `ShowWindowNow()` 负责恢复最小化／托盘隐藏并置前；不修改窗口宿主公开签名。
3. 原歌词 MethodChannel 单独回传 `settingsRequested`，Dart 服务新增只读 `settingsRequestedStream`；IK 请求适配器委托原 singleton 事件流，不注册第二个 handler。
4. IK 新增轻量事件桥接组件，入口提供 `onOpenSettings` 回调，接主程序既有 `/settings/lyrics` 导航。没有挂载桥接的旧入口不产生导航行为。
5. 主播放器新增可选 `onFloatingLyricsSettings` 回调，缺省 null，不显示额外按钮；新版入口显式接入同一路径。页面编辑保护与已有导航逻辑继续由主程序处理。

## 受影响调用方

| 位置 | 变动 |
| --- | --- |
| `windows/runner/compact_floating_lyrics_window.cpp` | 第六个工具栏按钮、齿轮绘制、命中和提示；保持旧五项动作索引 |
| `windows/runner/floating_lyrics_channel.cpp` | 新设置事件及仅当前进程主窗唤起；旧 GDI 窗口事件处理不变 |
| `lib/features/floating_lyrics/data/floating_lyrics_service.dart` | 增加事件流与内部适配器委托，不修改旧 show/update/hide 或控制枚举 |
| `lib/video_app/ik/ik_floating_lyrics.dart` | 可选入口桥接与订阅释放，不依赖新窗口／播放器控制接口 |
| `lib/video_app/video_app.dart` | 主任务把桥接与播放器按钮接到已存在的设置路由 |
| `lib/video_app/windows/windows_player_page.dart` | 播放页代理新增可选设置回调，默认不改变原布局 |

不变：原 GDI 窗口、旧 MethodChannel 名、已有公开方法签名、三个播放控制 action、设置数据键、Android 缺省行为。没有新运行时、网络请求或字体资源。

## 回滚

移除新版入口的设置桥接及可选播放器回调，并去掉 compact 工具栏的新齿轮即可恢复原五项工具栏。新增事件流可保留且无人订阅，对旧调用无影响。用户样式偏好和播放状态不需迁移或清理。

## 待验收场景

- 未锁定歌词 hover 可看见齿轮，提示“桌面歌词设置”；最窄尺寸仍可点且不压正文。
- 点击齿轮后只发送一次设置事件，播放状态、当前曲目、歌词开关和锁定状态不变。
- 主程序正常显示、最小化、托盘隐藏时，均能恢复并显示既有歌词设置页；重复点击不叠加无用页面。
- 没有歌曲时齿轮可用，三个播放按钮仍禁用；锁定时继续穿透，主播放器入口仍可进入设置解锁。
- 主播放器设置入口遵循既有编辑离开保护；旧可选回调缺省 null 的布局不变。
- 旧五项工具栏控制、关闭不复活、旧 GDI 与 Android 事件路径继续保持。

本轮不运行 tests、analyze、format 检查、GUI 或实时网络探测，不操作用户正在播放的进程和窗口，不提交代码。以上为待验收条件，不是通过结果。

## 本轮源码结果

compact 工具栏已加入第六项设置齿轮，显示顺序为上一首、播放／暂停、下一首、锁定、设置、关闭；原五项动作索引与分支保留。工具栏宽度为 214 逻辑像素，适配既有最小宽度 220；设置提示为“桌面歌词设置”。无歌曲时设置仍可点击，锁定后的整窗穿透规则不变。

原生新事件显式走 `settingsRequested`，先向当前进程标记主窗投递现有唤起消息，再回传 Dart。Dart 新增同名事件流，IK 委托服务转发 singleton 流。桥接构造为 `IkFloatingLyricsSettingsBridge(child: ..., onOpenSettings: ...)`，订阅随组件释放，路由回调由主任务接到现有页面。桥接缺省不挂载，旧入口不会新增导航。

本代理已完成原生、服务和桥接代码；主程序 `video_app.dart` 与播放器按钮分别由主任务／播放页代理接线。本轮未运行验证或构建，未提交，未操作任何用户窗口或进程。
