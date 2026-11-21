# IK Music 设置验收收尾票据

日期：2026-11-21。接续已发布的 IK Music 0.6.0 / build 11。用户要求处理剩余收尾，本票据仅修复既有测试的异步夹具，不变更产品实现或重新出包。

## 问题与真实场景

旧设置页的“自动换源”必须默认开启；用户点击后，开关显示和 Provider 同步关闭，再点击同步开启，每次点击都提出保存请求。`test/settings_page_test.dart` 原用例完整执行 body 后，真实 Hive 写入在 `testWidgets` 假时钟下没有收口，导致文件级 `tearDown` 等待 `Hive.close()`，因此长期 `skip: true`。

生产代码已有 `AutoSourceSwitchStore` 注入点和 `MemoryAutoSourceSwitchStore`；独立的 `test/settings_persistence_test.dart` 已使用该既有注入点验证 UI 写请求与真实 Hive 存储。旧用例未应用这个夹具，继续重复已知真实 I/O 与假时钟混用问题。

## 最小方案与影响范围

在旧 Widget 用例中注入既有内存 Store，保留原页面、真实点击、默认值、Provider 和开关显示的全部断言，并显式断言两次保存请求。删除已经被诊断证伪的 100ms `runAsync` 延迟和过期跳过注释，恢复用例执行，设置有界 30 秒超时。

真实存储由 plain `test` 验证：等待写入、关闭并重新打开同一 Hive 文件，再以新 Store/Notifier 读取；避免把同一个已打开 Box 的内存值误当成跨启动持久化。仅在需要时加强现有持久化用例，不增加测试专用产品抽象。

影响调用方仅为 `test/settings_page_test.dart` 和 `test/settings_persistence_test.dart` 的既有门。`lib/`、公开接口、存储键、默认开启行为、安装与发行包保持。回滚只撤销这两个测试文件的本轮夹具改动；不触碰用户数据。

本修复属于简单验收夹具缺陷，按用户铁律二在票据说明即可，不新增模块、复杂功能或外部接入。

## 验收门（先红后绿）

1. 红门：仅取消原用例跳过，原夹具和完整 body 保持，30 秒有界执行，记录实际超时/收尾结果。
2. 体验绿门：原页面默认开启，两个真实点击使 Provider 和开关显示按“关→开”同步，两次保存请求完整为 `[false, true]`，用例和文件级收尾均结束，无跳过。
3. 功能绿门：真实 Hive 写入 `false`、关闭重开后读回关闭；再写入 `true`、关闭重开后读回开启，原无 Box 降级和音效往返门保持。
4. 回归：完整执行设置页、设置持久化和自动换源三个相关测试文件；本轮修改文件格式与静态分析无问题。未执行新一轮全仓或产品出包，历史正式发行全量计数不改写。

## 执行结果

红门执行：

```powershell
flutter test --no-pub -j 1 test/settings_page_test.dart --plain-name 'the 自动换源 switch is wired to the provider and flips it' --reporter expanded
```

原夹具仅取消跳过、设置 30 秒有界超时，实际出现 `TimeoutException after 0:00:30.000000`，退出码 1；报告时长 31 秒，总耗时 99.20 秒包含首次编译加载。没有将编译加载耗时写成用例本身挂起。

绿门执行：

```powershell
flutter test --no-pub -j 1 test/settings_page_test.dart test/settings_persistence_test.dart test/source_match_test.dart --reporter expanded
flutter analyze --no-pub
dart format test/settings_page_test.dart test/settings_persistence_test.dart
```

三个相关文件完整运行：设置页 18 条、设置持久化 5 条、自动换源 29 条，合计 **52 条通过、0 跳过、0 失败**；测试报告 8 秒、命令总耗时 14.78 秒。原自动换源 Widget 门恢复执行，两个真实点击与显示、Provider、完整保存请求 `[false, true]` 同时通过。真实 Hive 的两次关闭重开读取都通过。无 Box 的既有降级门会打印预期的读写诊断，但断言和总退出码均成功。

全仓静态分析 **0 问题、退出码 0**，报告 102.1 秒、总耗时 105.73 秒。两份修改测试格式 **0 变化**，`git diff --check` 通过。本轮仅改测试夹具，不重新执行全仓回归或出包；正式 build 11 的既有 2095/19 全量记录属于已发布构建的历史证据，不改写成这次定向门的结果。

红门日志 SHA-256：`DE9374E52D0ADA54C34B8CFA0E6C114AFAF465702D6B87DCAE2C5E967D285A58`。绿色相关门日志 SHA-256：`D234A8DA2FBDE7D250053E3AD9EDE376103BDE485EE8D1BCDE9A59279B4CCA08`。七份本轮日志与结果已逐文件核对原件和正式归档的长度、SHA-256 完全相同；正式位置为聊天 `outputs/IK-Music-0.6.0-build11/验收证据/设置验收收尾-20261121`，归档清单长期保留。

临时文件全部由本轮新建于聊天 `work/ik-settings-test-close-20261121`。执行前记录旧 Temp 目录清单、执行后取精确差集，唯一红门残留为 `C:/Users/Sun/AppData/Local/Temp/mconnect_settings_test_552d1443`（2026-11-21 16:06:38 创建，内为样例背景、临时 Hive 和诊断日志，四文件共 277 字节）；绿色用例正常自行清理。收口任务的临时文件批量清理及缩小到单个旧下载副本的删除均被自动审批拒绝；本轮新建的四个样例文件另按精确绝对路径执行非递归删除，也被拒绝。三次只返回 `blocked by policy`，重新检查四样例仍在；本轮新目录与工作日志列入真实遗留，不宣称已删除，不换工具或语言绕过。正式测试和本票据长期保留。
