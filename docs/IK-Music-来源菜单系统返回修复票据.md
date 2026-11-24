# IK Music 来源菜单系统返回修复票据

记录时间：2026-11-24T21:23:03+08:00。本票据由本轮 Codex `/root/delivery_support` 新建，属于正式长期交付物。

## 状态与授权

**源码已实现，`handlePopRoute()` 确定性门已由红转绿。** 原生 A09-N 在 5a5 成品的首红继续有效，修后新 APK 尚待复验。来源菜单和移动键盘的开关可独立回滚。

这是既有来源菜单取消交互的简单缺陷补门。负责人的授权只覆盖当前紧凑搜索来源下拉 opt-in、全部12个直接产品调用方清单和正式门：新增 `dismissOnSystemBack=false` 与独立 Search flag；仅 `main_video` 移动平台真启用，Windows与另外11处缺省保持。其它菜单是否扩大启用，由负责人依据后续新 Android 实测决定，本轮不广泛开启。

## 一、真实场景与原生首红

源提交：`5a5f3d8d97b582b2dbd1f21826eaf44ca6225b46`。新 x86_64 APK SHA-256：`b495f39a30b130b432e127316a536030860421b5198258a0e99edd7253eb7153`。本轮320×640新包 PID2417。

场景：搜索music结果页 → 打开“全部来源”下拉 → 在菜单内实际滚动到网易云/酷狗 → 发送 Android 系统 KEYCODE_BACK（实际命令69） → 检查当前页面与菜单。

预期：首次系统返回关闭菜单，仍在搜索结果页；query、filter和结果滚动位置不变，不执行 `onChanged`。菜单已关后的再次返回按既有导航处理。

实际：新12PNG/XML为Android启动器；当前Activity为 `com.android.launcher3/.uioverrides.QuickstepLauncher`。当前搜索query节点不再可见，APP当前Activity退出。此处中断此前连续操作，后续恢复入口需要另记，不能合并声称连续场景全部通过。

全部来源、本地、QQ音乐、网易云、酷狗均在本轮新树实际出现，菜单可达事实保留；返回门红不能抹掉已测可达结果。原件由验收代理采集，作者只读核对首红JSON、源码和接口，不执行UI/ADB/安装。

正式首红：[Android-首错A09-来源菜单系统返回退出APP.json](C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/IK-Music-0.6.1-build12/验收证据/新成品-5a5f3d8-20261124/Android-首错A09-来源菜单系统返回退出APP.json)，4691字节，SHA-256 `b493b7daf486c43751d24c70dfe75c2e68d567b7f4c9904c936996b139806aae`。该文件包含动作61–72和全部8项证据全路径、长度、SHA，不抽样丢弃。

| 原件（相对上述证据根目录） | 字节数 | SHA-256 |
| --- | ---: | --- |
| Android-新截图/10-新搜索来源下拉菜单.png | 36977 | `4c004a8aff3356e0dd42528545fdf0a66e803baa5f06635bbda1c989055ca206` |
| Android-新截图/10-新搜索来源下拉菜单.xml | 17249 | `d232d4a6c3603a5039252bc2b3b279ac6189d21d12e2ca4c07669495c5ef4289` |
| Android-新截图/11-来源下拉滚动到其余平台.png | 36577 | `37f795671f1c72b42d88abe12330b86f3c0ba94874abb1a95f027ed16f374a7b` |
| Android-新截图/11-来源下拉滚动到其余平台.xml | 17243 | `550f969fa2edd63b02127fe753a7ff9ea56f3ed25f3d8d13e37adfeb87f46704` |
| Android-新截图/12-系统返回关闭来源菜单保持查询.png | 107849 | `cc39a04221582aac847cb11a64256e6eefce20101b0bc0131a6835cf0c4d08c7` |
| Android-新截图/12-系统返回关闭来源菜单保持查询.xml | 9230 | `77e09bef3bba095b70b8185d1c8ea9e81a32e12c3b88f35e04eb43e96c9f81b6` |
| Android-逐命令原始输出/0073-stdout.log | 24265 | `fbbf9ab1622c8af88e70e812c6ebd090938b5abafe0604d8eb49b4b32524cf27` |
| Android-来源菜单系统Back退出段完整日志-PID2417.log | 114725 | `5281224fd30b4d824b7bd8013bf207404f0ab9b53feace3ad9b87fbb072e1a83` |

## 二、根因与方案比较

紧凑搜索来源控件在 `lib/video_app/ik/ik_search_workspace.dart:388` 使用 `IkSelect`。其统一实现 `ik_controls.dart:36` 为 MenuAnchor，builder（89–96）只取controller开/关；当前页面/外壳未为菜单打开状态注册应用层 Android系统返回消费或局部历史。全lib的PopScope只在独立source_manager、kugou_playlists路由，不保护当前搜索。

菜单浮层不是一个会先弹出的独立导航路由；应用没有在当前ModalRoute上告知系统“菜单尚开，应先取消”。Android系统返回继续进入根导航并退出Activity，与首红一致。键盘Escape与Android系统返回是不同事件路径，原有Escape门不能覆盖此错误。

本机Flutter接口只读确认：MenuAnchor提供controller/onOpen/onClose，PopScope提供canPop/onPopInvokedWithResult，并注册当前ModalRoute的pop entry。采用本机当前接口，不新增依赖或修改SDK。

| 方案 | 影响 | 结论 |
| --- | --- | --- |
| 全局拦截所有返回，或把下拉改成另一种路由/弹层 | 改变每个导航/菜单及Windows公开缺省；需要更大调用方和回归范围。 | 不推荐。 |
| 当前来源显式启用局部PopScope，统一组件新增默认false能力 | 菜单开时拒绝路由pop，仅关闭菜单；关后恢复既有导航。原默认构造保持旧树和动作路径，只在已批准入口启用。 | 推荐，已获负责人确认。 |

## 三、接口与状态设计

公开 `IkSelect` 新增可选 bool `dismissOnSystemBack = false`，现有参数、回调、返回类型及默认行为不变。opt-in分支持有菜单controller，MenuAnchor实际开/关回调同步当前菜单开态；该态仅驱动局部PopScope。

菜单打开：`canPop=false`。系统返回尝试的回调中，仅当未发生route pop且当前菜单仍开时close，不调用onChanged，不改filter/query。菜单关闭：恢复 `canPop=true`。选择、外点、Escape继续通过原MenuAnchor动作关闭；选择原回调仍只执行一次。dispose/路由移除不得在已释放State上setState，浮层/焦点/controller按原生命周期清理。仅增加本能力需要的最少状态，不新增全局返回管理器。

公开 `IkSearchWorkspace` 新增可选 bool `dismissSourceMenuOnBack = false`，只传给 `_compactSearchHeader` 中紧凑来源下拉的 `dismissOnSystemBack`。同一独立可选字段经 `VideoMusicApp` → 私有 `_VideoHome` → workspace搜索页传递。`main_video` 仅在 `!PlatformUtils.isDesktop` 时明确启用。键盘布局字段 `mobileKeyboardLayout` 与此字段各自默认false、各自回滚。

宽度/页面布局不参与返回消费条件；真正条件是此入口明确opt-in且菜单实际已开。Windows入口为false，默认调用方没有新增PopScope树。search旧非对齐/非紧凑下拉、推荐来源选择、其它业务下拉保持当前实现。

## 四、全部12个产品调用方与公开入口

实施前 `rg` 全量直接构造结果如下。只开启第10项，另外11项缺省保留。

| 序号 | 文件/位置 | 本次处置 |
| ---: | --- | --- |
| 1 | lib/video_app/ik/ik_library_workspace.dart:372 | 保持缺省false。 |
| 2 | lib/features/smart_playlists/presentation/pages/smart_playlist_editor_page.dart:255 | 保持缺省false。 |
| 3 | lib/video_app/ik/ik_settings_workspace.dart:297 | 保持缺省false。 |
| 4 | lib/video_app/ik/ik_settings_workspace.dart:556 | 保持缺省false。 |
| 5 | lib/video_app/ik/ik_settings_workspace.dart:725 | 保持缺省false。 |
| 6 | lib/video_app/ik/ik_settings_workspace.dart:1037 | 保持缺省false。 |
| 7 | lib/video_app/ik/ik_settings_workspace.dart:1411 | 保持缺省false。 |
| 8 | lib/video_app/ik/ik_search_workspace.dart:110 | 非对齐旧搜索，保持缺省false。 |
| 9 | lib/video_app/ik/ik_search_workspace.dart:249 | 非紧凑搜索来源，保持缺省false。 |
| 10 | lib/video_app/ik/ik_search_workspace.dart:388 | 当前紧凑来源；只传独立可选Search flag。 |
| 11 | lib/video_app/ik/ik_search_workspace.dart:536 | 推荐来源选择，保持缺省false。 |
| 12 | lib/features/library/presentation/pages/platform_playlists_page.dart:717 | 保持缺省false。 |

IkSelect构造定义位于 `ik_controls.dart:6`。直接测试构造位于 `test/ik_workspace_test.dart:61`、`test/ik_settings_alignment_test.dart:135`；其它测试中的类型Finder/读取不是新产品构造。既有默认测试不改成广泛opt-in；新增正式B系列门可追加到既有workspace测试。

IkSearchWorkspace唯一产品调用为 `video_app.dart:2651`。其既有直接测试调用为 `test/ik_library_search_density_test.dart:1221/1241`、`test/ik_lists_alignment_test.dart:71/114/263`，均保持公开缺省。VideoMusicApp入口及全部既有直接测试调用已列在A05票据第四节；本次仅新增第二个独立可选字段的传递，不修改既有签名参数或行为。

授权改动文件：`lib/main_video.dart`、`lib/video_app/video_app.dart`、`lib/video_app/ik/ik_controls.dart`、`lib/video_app/ik/ik_search_workspace.dart`、既有相关正式test与本票据。A05的ik_workspace布局文件由同一任务独立处理，两个修复不互相覆盖。

## 五、门先行

| 门 | 真实场景 | 执行与状态 |
| --- | --- | --- |
| B01-N 原生首红 | 新5a5、搜索music、来源菜单开/滚动后Android系统Back | 退出当前Activity到launcher，**已红**，原件保留。 |
| B01-D 系统返回取消 | 真实MenuAnchor置于真实Navigator/ModalRoute中，query=music、filter已选、结果已滚动，菜单开 | 先在当前组件跑真实 `tester.binding.handlePopRoute()` 红；修后首次只关闭菜单，原route/page元素、query、filter、scroll不变，onChanged计数不增加。禁止用Escape代替系统返回。 |
| B02 选择与多类取消 | 菜单打开、选择、重新打开、外点取消/Escape/系统返回 | 选择回调恰一次，所选值更新且菜单关闭；所有取消不变更值，不额外执行回调，恢复触发器操作。 |
| B03 第二次返回 | 菜单已关后再次handlePopRoute | 恢复原导航行为，离开测试搜索route，页面dispose；不能一直拦返回。 |
| B04 dispose | 浮层开时route移除或widget卸载 | 没有setState-after-dispose或残留菜单/焦点异常；State和浮层按真实生命周期销毁。 |
| B05 缺省/Windows | 省略参数、显式false、Windows入口、其它11调用 | 原返回和菜单动作保持；既有U03键盘选择/Escape及设置/语义门不退。 |
| B06 真入口传递 | main_video移动入口 → App/Home/Search → 紧凑来源 | 两独立flag默认false；移动仅紧凑来源true，Windowsfalse；实际组件与路由行为验证，不能仅grep属性冒充全部体验门。 |
| B07 新原生复验 | 负责人统一构建的新提交/新APK，真实系统Back | 新PNG/XML、当前Activity与新PID完整日志证明首次仍在APP/query保留，取消不执行，第二次导航正常；旧5a5仍记红，不混用成品。 |

确定性门不含大模型、账号、真实歌曲或网络；在既有test文件追加正式长期用例，不创建临时tests目录。全部执行场景在结果逐项列出，不用抽样或无异常冒充覆盖。

测试按A05已授权SDK串行窗口进行：必要时仅在受控test作用域附加同版本官方固定 `test-sqlite3` 输入配置，pubspec原字节只存内存，finally恢复并记录原SHA和后SHA；不提交hook配置，不改全局cache/SDK，不安装工具。第一次网络环境失败独立记账，不冒充B或K红门。全仓test及新成品构建由负责人收到最终源码后统一安排。

## 六、实施顺序与回滚

1. 本票据正式落盘，保留B01-N原件及全部12调用清单。
2. 在现有workspace测试中建立真实handlePopRoute体验/功能红门，当前代码实际运行失败后再实施。
3. 仅增加默认false的新菜单能力与独立Search/App传递；main_video移动端显式启用。
4. 定向红→绿，并执行选择、三类取消、第二次返回、dispose和缺省兼容门；format/analyze。
5. 将最终源码、门结果、原/后pubspecSHA及剩余新原生门交负责人，等待统一全仓/成品复验。

优先回滚仅把main_video的 `dismissSourceMenuOnBack` 置false或省略；新可选能力/字段可以保留但不激活。A05的 `mobileKeyboardLayout` 无须回滚。全撤时只撤本票据新增传递及opt-in局部菜单分支，不回退别的任务源码，不删除原有或正式新测试/证据。

无数据库/账号/签名/下载/播放协议变更，无数据迁移。回滚需核默认调用方、原导航及正式门状态；回滚后原系统返回首红恢复，应如实记红。

## 七、当前边界

其它菜单的新 Android 实测若发现同类缺陷，先记录实际场景及验收门，再由负责人确认新增调用方。本次来源菜单开关的范围见第四节。

本任务是代码控制流和确定性事件/契约核对，无需Jev。未操作GUI/ADB/安装/进程/音乐凭据，未重试历史拒绝清理；正式票据、原生证据和新增正式门长期保留。

## 八、2026-11-24 定向结果

实施前 B01-D 已实际执行。菜单打开后模拟系统返回，`handlePopRoute()` 弹出测试搜索路由，预期保留的页面元素计数从一变为零，测试失败。首红日志 `Android-A09-handlePopRoute-红门.log` 为 2274 字节，SHA-256 `bd94ace5e9e65e2940588e7546769a44ebd43538d2178e5bc3b8d311db39a072`。

`IkSelect` 新增默认 `false` 的 `dismissOnSystemBack`。启用时用持久 `MenuController` 的实际开态更新局部 `PopScope`。打开时系统返回关闭菜单，恢复关闭态后下一次返回依照原导航处理。`dismissSourceMenuOnBack` 从 `main_video` 经 `VideoMusicApp`、`_VideoHome`、`IkSearchWorkspace` 传到紧凑搜索来源。它在非桌面入口开启，所有公开缺省均为 `false`，其它 11 处构造调用保留缺省。

| 门 | 实际执行结果 |
| --- | --- |
| B01-D、B03 | **通过**。实际 Navigator 中，首次 `handlePopRoute()` 关闭 5 项来源菜单，保留现有页面实例、`music`、网易云筛选与结果滚动位置，选择回调计数仍为 0。第二次返回离开搜索并销毁页面。 |
| B02 | **通过**。选择酷狗仅触发一次回调。分别重新打开菜单并外点、按 Escape、模拟系统返回，均成功关闭，保持酷狗和 `music`，回调计数仍为 1。 |
| B04 | **通过**。浮层打开时移除路由，页面正常销毁，浮层消失，未出现异常。 |
| B05 | **通过已执行项**。在 Windows 平台覆盖下，省略参数和显式 `false` 各验证一次原返回行为。既有 U03 键盘选择及 Escape 继续通过。设置与完整语义树仍待全仓门。 |
| B06 | 四层入口参数传递和唯一启用调用方已核对到源码。本轮系统返回行为门跑在实际 Navigator 的受控页面，完整产品启动及搜索结果场景仍待验证。 |
| B07 | 等待新 Android APK 实测，覆盖来源菜单内部滚动、真实 Back、保留 Activity、查询、筛选、结果滚动和第二次返回。 |

两个既有文件共 **42/42 项**通过，无跳过。`ik_workspace_test.dart` 24 项包含 5 项 B 系列门与 19 项既有门，`ik_playback_bar_test.dart` 18 项。格式化 7 文件 0 变化，7 文件定向静态分析无问题。三份正式定向日志及 `pubspec.yaml` 恢复前后同一 SHA-256 见[移动端键盘遮挡修复票据](IK-Music-移动端键盘遮挡修复票据.md)第八节。原生和确定性首红证据保留，正式测试继续保留在既有 workspace 测试文件。

### 2026-11-24 全仓结果

三项修复合并后的全仓测试通过，243 套、2,700 项通过、18 项沿用原跳过原因、0 项失败。原待验的设置与语义树套件均已通过。全仓格式与静态分析通过。完整入口的原生返回场景 B07 仍待使用新 Android APK 复验。[全仓逐案解析回执](<C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/IK-Music-0.6.1-build12/验收证据/移动端修复-20261124/三项修复最终全仓/全仓逐案解析回执.json>)。
