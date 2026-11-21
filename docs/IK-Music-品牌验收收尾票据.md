# IK Music 品牌验收收尾票据

日期：2026-11-21。接续已经安装和公开发布的 IK Music 0.6.0 / build 11，本票据只修正历史验收字面量，不改产品、README、安装身份或发行包。

## 问题与真实场景

用户已经指定客户端名称为 **IK Music**，并要求 GitHub 仓库改为 **sun-dove/ik-music**；实际仓库更名、README、发行链接和本地 origin 已同步。当前首页必须显示这两个明确名称，Android 原 Mconnect 默认入口、稳定版本与图标资产的兼容断言继续执行。

`test/windows_music_brand_test.dart` 最后一个门仍要求 README 含旧仓库地址 `https://github.com/sun-dove/yueyin-music`、历史候选归属名 `Dingjian` 和小写 `ik`。Dingjian 约定来自《DJ-Music-改版设计与验收计划》《DJ-Music-品牌与图标接入票据》的 0.5.1 历史阶段；README 在 `3c37d6e` 已按后续用户要求更新，验收门没有同步。

对 `d5f88c4` 执行的完整 Linux CI **44884439039** 已产生真实红门：该用例第 348 行期待旧 URL，而实际首页为 `# IK Music`、`sun-dove/ik-music` 及新下载链接。失败首先发生在旧 URL 断言，后面的 Dingjian 断言未继续执行；不将未执行断言写成另一项 CI 失败。该文件其余五门在同次 CI 已成功。

## 最小修正与影响范围

只更新最后一个门的标题及四处 README 字面量，明确校验 `https://github.com/sun-dove/ik-music`、`sun-dove/ik-music` 和 `IK Music`。保留该门所有 Android 原 Mconnect 条件、版本、资源及入口断言；同文件其他五门完整保持。继续用明确名称，不改成任意名称或宽泛匹配。

受影响调用方仅为 `test/windows_music_brand_test.dart` 的该门。生产 `lib/`、Android、Windows、installer、README 与已发布字节不变。回滚只撤销该测试本轮字面量修改，不能为了恢复过期测试要求而回退用户已确认的新品牌。

本修复属于简单验收断言缺陷，按用户铁律二在票据说明即可；不新增模块、复杂功能或外部接入。

## 验收门

1. 红门来源：保留 `44884439039` 原始 CI 日志与失败组摘录，明确原期待值、实际值和第 348 行，不重复全仓。
2. 品牌功能与体验门：完整执行 `windows_music_brand_test.dart`，当前首页和文案精确匹配 IK Music 与 ik-music，原安装/数据身份和跨平台图标断言保持。
3. 相邻回归：完整执行 `ik_brand_test.dart` 与 `version_sync_test.dart`，验证用户可见标题、品牌重复项、版本与原 Mconnect 七个同步点；不重复已在新 CI 成功的设置 52 门。
4. 仅本测试格式和定向静态分析无问题。CI 全量的最终结果由收口记录补充，不把局部通过冒充远端全量成功。

## 执行与正式证据

实际绿门命令：

```powershell
flutter test --no-pub -j 1 test/windows_music_brand_test.dart test/ik_brand_test.dart test/version_sync_test.dart --reporter expanded
dart analyze test/windows_music_brand_test.dart
dart format --output=none --set-exit-if-changed test/windows_music_brand_test.dart
```

完整执行三个文件：Windows 品牌 **6 条**、IK 品牌 **2 条**、版本同步 **14 条**，合计 **22 条通过、0 跳过、0 失败、退出码 0**。测试报告 4 秒，命令总耗时 12.86 秒。版本门明确报告 **7/7 同步点**，没有省略原 Mconnect 项或抽样跨平台图标断言。

定向静态分析 **0 问题、退出码 0**，耗时 2.60 秒；格式 **1 文件、0 变化**，`git diff --check` 通过。本轮差异恰为该测试标题和四个明确字面量，README 与生产 `lib/`、Windows、Android、installer 均无差异。不重新出包、全仓测试或重复设置 52 门；后续两项远端 CI 的终态由收口任务继续跟进。

红绿证据直接放在聊天正式交付目录 `outputs/IK-Music-0.6.0-build11/验收证据/收尾CI-20261121/品牌门修正-20261121`，五文件为：`原始CI红门摘录.log`、`定向绿门.log`、`定向分析.log`、`格式检查.log`、`证据索引.json`。索引含原始 CI 完整日志散列、基线提交、命令结果、耗时和四份证据日志散列。

原始 CI 红门摘录 SHA-256：`E5DEEFB660EDBE5A1051519F10BCA0639D143C7E2427EFAB4A46640E45D4F44B`。定向绿门日志 SHA-256：`72A943AFA7D7DDCFF0AC6E376DB2254256A3606A71DCC7DEDA39DE77CBC297D7`。

该目录与原始 CI 日志、本票据及正式测试一起长期保留，属于明确交付的红绿证据；不新建临时 work、样例或脚本。三个门只读取既有资源，没有创建测试样例目录；正常结束后未发现 `dart`、`flutter_tester`、`dartaotruntime` 进程残留。
