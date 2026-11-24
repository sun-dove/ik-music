# IK Music 底栏播放与音效导航修复票据

2026-11-24。负责人已确认这是既有快捷入口的简单缺陷。新源码已实现，确定性首红和修后定向结果已留证，新成品复验待执行。

## 场景与根因

在 5a5f3d8 成品打开设置，点中“备份与恢复”后，点击底栏带“播放与音效”提示的均衡器按钮。预期在当前工作区显示播放与音效内容并保留同一个设置页面的状态。Windows 点击时和稳定后都留在备份页。Android 独立复现的首次稳定页面与延时页面相同，仍显示备份内容。

原件位于 [5a5f3d8 验收证据目录](<C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/IK-Music-0.6.1-build12/验收证据/新成品-5a5f3d8-20261124>)。

| 证据 | 字节数 | SHA-256 |
| --- | ---: | --- |
| Windows-运行01-049-1.png | 58190 | `1b3c660773c93091a5d6edcdc6a9e2340701570d7a18312a59a3c7710c99fe0d` |
| Windows-运行01-050-1.png | 58045 | `3f8a8a907ca7d746b7e9cf18bfbcd386ba4dfb66f06b7f6d18e821db9e82ecac` |
| 续验-20261124-Android原始证据/0068-stdout-底栏音效-首个点击后稳定界面.xml | 13729 | `dc3fb74219acb0976f802736c47a979f782025fecd7494eefbe60917c13fd4b8` |
| 续验-20261124-Android原始证据/0071-stdout-底栏音效-延时复核.xml | 13729 | `dc3fb74219acb0976f802736c47a979f782025fecd7494eefbe60917c13fd4b8` |

在根工作区，父级 `_settingsSection` 初始为 `audio`。用户选择备份时，设置组件只修改自己的 `_section`。根底栏的音效入口再次给父级赋值 `audio`，传给组件的 `initialSection` 与上次相同，组件的 `didUpdateWidget` 因此保留了备份区。切换整个设置组件的 `Key` 会销毁当前状态，使未提交草稿和导入预览丢失。

## 方案与兼容范围

给 `IkSettingsWorkspace` 新增可选 `sectionRequest`，默认 `0`。当合法目标 `initialSection` 改变，或请求序号改变时，在现有组件 State 中采用目标。根工作区的底栏音效入口只在对齐模式下递增私有请求序号。明确传入独立路由 section 的设置实例使用默认序号。开关、账号、播放、备份和音效存储继续使用原调用方式。

| 直接调用与路径 | 处置 |
| --- | --- |
| `video_app.dart` 的 `_workspaceSettings()` 根设置实例 | 传入根底栏音效请求序号。旧非对齐模式序号保持 0。 |
| `video_app.dart` 的 `_workspaceSettings(section)` | 独立 `/settings/:section` 使用默认请求序号。详情底栏和完整播放器底栏的 `/settings/audio` 路由继续走这条路径。 |
| `video_app.dart` 的曲库 `onAccounts` 和根工作区 `onAccount` | 继续按原设置目标传递方式进入账号区。 |
| `ik_settings_workspace_test.dart`、`ik_settings_alignment_test.dart` 的直接构造 | 使用原参数和新字段缺省值，纳入回归。 |
| `ik_playback_bar.dart` 的两种公开构造 | 保留 `onAudio` 签名与按钮行为。 |

回滚优先撤销根底栏的序号递增，或同时撤回新字段与它在更新钩子中的分支。回滚后需要重新核验底栏入口和原调用方，正式回归门和证据保留。

## 可执行验收门

| 门 | 验证 |
| --- | --- |
| E01 成品首红 | Windows 和 Android 都在备份内容中点真实音效按钮后停在备份。保留上述原件。 |
| E02 根工作区确定性门 | 真实 `VideoMusicApp` 的对齐工作区。进入备份区后，点实际底栏音效按钮，验证音效正文可命中、备份正文消失，且设置 State 和根路由实例保持。重复切换，确认同一份未导入的备份预览仍可见。 |
| E03 兼容回归 | 旧设置在备份区再次点击根设置导航，通过重建后的新 widget 验证备份区和 State 保留。真实入口集成、设置组件与对齐门验证原分区导航和详情播放器音效路由。 |
| E04 新成品 | 使用新 Windows 和 Android 包复测同一备份到音效场景并保存稳定画面。 |

早前全仓测试因这项成品缺陷主动停止，日志、输入清单与中止回执保留在 [移动端修复证据目录](<C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/IK-Music-0.6.1-build12/验收证据/移动端修复-20261124>)。该轮在中止前记录 363 项通过，未到历史跳过门，也没有全仓 `done` 事件。

## 确定性首红

只加入 E02 门后运行 `flutter test --no-pub -j 1 test/ik_app_integration_test.dart --plain-name 'E02 根底栏音效从备份切到播放与音效并保留设置状态' --machine`。旧代码确认备份正文与底栏音效按钮可命中，点击后音效正文的可命中节点实际为 0，机器终态 `success=false`，退出码 1。日志 `音效导航-E02-正式首红.machine.jsonl` 为 4231 字节，SHA-256 `0e13b7686c9f2a98245daa681148d9e0ca3be337ce8e63c36700d0ce9cd6da5a`，同名 stderr 为空。依照已确认方案，在保留原分区选择更新条件的同时，加上有效目标的请求序号触发，并扩充同一 State 的备份预览保留门和旧缺省重建门。

## 修后定向结果

`ik_app_integration_test.dart`、`ik_settings_workspace_test.dart` 和 `ik_settings_alignment_test.dart` 共 130 项通过，零跳过、零失败。E02 两次从备份切换到音效，回到备份能继续查看同一份导入预览，文件选择器只调用一次。期间保留设置 State 和根路由。E03 确认旧设置 widget 再次构建后仍留在备份分区。三份定向文件共用日志 `音效导航-三文件定向.machine.jsonl`，109316 字节，SHA-256 `a29682da8359f27a80042397a5d9cb9a6bd13f07aa47813c641b89f551d06656`。测试退出 0，`pubspec.yaml` 检查前后 SHA-256 同为 `7677e58fad5fd4dc09dcfcf112522ed4bc7c29f19440755fb3da206d9f5faed7`。

## 最终全仓结果

三项修复合并通过全部 243 套测试，2,700 项可见用例通过、18 项跳过、0 项失败。跳过的用例与原因逐项匹配旧基线，另外 267 项套件加载和设置收尾等隐藏事件均成功。旧基线用例全部出现，新增 21 项均通过。格式检查 591 个文件、0 处变化，静态分析无问题。600 项全量输入的首尾清单 SHA-256 均为 `77d622b5b34338cc9a1406b58931764ea255928db342ace5676891d6d90d88d8`。详见[全仓逐案解析回执](<C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/IK-Music-0.6.1-build12/验收证据/移动端修复-20261124/三项修复最终全仓/全仓逐案解析回执.json>)。

E04 待用新 Windows 和 Android 成品复验。
