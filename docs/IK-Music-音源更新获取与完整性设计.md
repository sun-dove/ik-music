# 音源更新获取与完整性设计

## 目标与边界

用户要求检查和更新真实音源。现有内置目录只保存签入时固定版本，旧导入器将下载和运行时inspect放在一起；若“检查更新”直接复用导入器，会在用户仅查看是否变化时执行第三方初始化。本次新增独立获取器，仅下载、解析静态头部和核对完整性；root负责许可／平台限制、检查结果、更新草稿、运行时inspect、自动更新可选开关及发布。

新增代码仅 `lib/video_app/built_in/source_update_fetcher.dart`，旧目录、固定导入器、运行时、存储和公开方法均不改。所有项目文档使用中文。本轮不运行产品、初始化脚本、测试、analyze、format或构建；公开仓库元数据只读研究不代表产品验收。

## 公开资料与本轮观察

公开仓库为 [pdone/lx-music-source](https://github.com/pdone/lx-music-source)。本次 `git ls-remote refs/heads/main` 与GitHub页面均指向提交 `65d3b23c0ba356cb3117979a53493ab9f7473c46`。固定提交页面的 `changqing/latest.js` 展示实际JavaScript，头部有 `@name 长青SVIP音源/@version 1.3.0`，约27KB；`fish/latest.js` 为约625KB实际文件。这里只读取元数据／可见头部，没有执行任何脚本，不把抽样页面当全部目录已证明。

GitHub匿名REST本轮返回HTTP403 `rate limit exceeded`，因此没有取得当前完整recursive tree，也没有声称验证所有latest文件模式。产品在运行时先通过 [Git reference接口](https://docs.github.com/en/rest/git/refs#get-a-reference) 固定main提交，再通过 [Git commit接口](https://docs.github.com/en/rest/git/commits#get-a-commit) 获取其tree SHA，最后用 [Git tree接口](https://docs.github.com/en/rest/git/trees#get-a-tree) 获取完整递归树。采用Git对象接口避免普通commits接口附带整个提交补丁，触发元数据大小限制。不能用页面显示、旧hash或“latest”名称代替mode／size／blob SHA证据。限额失败应明确报告，不退到不可校验的浮动下载。

## 方案对比

方案A直接下载 `main/<目录>/latest.js` 后初始化。获取过程可能跨越main变更，没有上游blob证明，“检查”还会执行第三方脚本，不采用。

方案B一轮固定commit和完整tree，下载该commit对应blob；校验Git blob SHA-1及字节数通过后返回静态结果。`refresh` 每轮只读取一次元数据；同轮多源共用快照。采用B。镜像只允许同仓库、同commit、同实际路径，不凭空加入新代理。

自定义源没有可信Git tree时采用原始导入地址读取，复用已有 `lxImportUri/lxDownloadUris` 的GitHub页面转raw和同文件镜像逻辑；转换时保留原地址query，带query只使用标准化后的原地址，避免镜像丢弃查询语义。不将用户固定版本地址改成latest，不跟随脚本内声明的update_url，不把普通SHA-256称上游验证。运行时inspect仍由root在用户更新流程明确调用。

## 接口与数据

```dart
class IkSourceUpdateFetcher {
  IkSourceUpdateFetcher({Dio? dio});
  Future<void> refresh(CancelToken token);
  Future<IkFetchedSourceUpdate> fetch(IkCatalogEntry entry, CancelToken token);
  Future<IkFetchedSourceUpdate> fetchCustom(Uri origin, CancelToken token);
  void dispose();
}
```

`IkFetchedSourceUpdate` 字段：`script/name/version/sha256/contentSha256` 为String，`origin` 为Uri，`upstreamCommit/upstreamBlobSha1/path` 为可空String，`byteLength` 为原始字节数。`contentSha256`对下载原字节计算；`sha256`对严格UTF-8解码并剥单个UTF-8 BOM后的script重新编码计算，与现有 `LxSourceConfig.sha256` 语义一致。内置origin固定commit＋最终真实路径，自定义origin为标准化后的原导入地址；自定义upstream三字段为空。

内置源只接受 `pdone:[a-z0-9]+`，寻找 `<sourceKey后半>/latest.js`。必须为tree中blob，普通文件mode只接受100644／100755。若mode120000为symlink，先读取并核对该链接blob，再将其UTF-8内容解释为同目录单个 `.js` 文件名（可有 `./` 前缀），不允许绝对路径、父目录、URL、多行或跨目录；目标必须在同一个已确认tree中并且是普通blob。拒绝链式symlink、目录和submodule。不执行链接文本或脚本。

下载依次使用 `raw.githubusercontent.com/pdone/lx-music-source/<commit>/<path>` 与现有 `fastly.jsdelivr.net/gh/pdone/lx-music-source@<commit>/<path>`。原始字节数必须等于tree的size，Git blob SHA-1按 `sha1(UTF8('blob '+字节数+'\0') + 原字节)` 核对。任一来源不匹配不得返回；其它来源只有同一blob可尝试。静态头部name/version采用现有V3相同正则，name须非空且不超过160字符。HTML、无效UTF-8和空脚本均失败。

## 网络、取消与错误

默认复用 `createLxDio` 的HTTPS／公网解析守卫，不读取用户凭据。获取器额外检查HTTPS、无userinfo、无fragment且有host，关闭重定向；下载每文件最多1MiB，元数据正文同样设1MiB上限。每次refresh／fetch／fetchCustom总预算30秒，包含镜像尝试与必要首次快照读取；连接与读写沿用10秒单次上限。超时／用户取消要取消实际网络token并停止后续镜像，不让运行时先收到脚本。

错误复用 `LxSourceException`，区分 `rateLimited/timeout/cancelled/integrity/size/metadata/sourceMissing/invalidEncoding/script/link/download`。GitHub HTTP429或403且剩余额度0明确报告匿名请求限额，并可显示服务返回的重置时间；普通403不得笼统当限额。失败refresh清除旧快照，不悄悄继续用上轮数据；成功后同轮fetch复用固定快照。

## 实施与回滚

先本票据与体验门，再新增获取器与不可变结果模型，最后root单独接检查／草稿更新／可选自动更新。获取器不调用inspect，不修改source entries或enabled状态。撤销root新装配即可回滚；新增文件可保留不影响旧固定导入流程。没有新依赖或新后台服务。

## 待执行门

| 真实场景 | 体验／调用方应看到 | 获取契约 |
| --- | --- | --- |
| main有新版本 | 显示真实静态版本及变更hash，尚未启用 | 一轮同commit/tree，普通blob字节数和Git SHA-1匹配后才返回 |
| 无变化或自定义固定地址 | 明确内容未变，固定URL可能没有新内容 | 比较规范script SHA-256；不猜latest，不执行初始化 |
| 安全symlink | 返回同tree目标真实脚本 | 链接blob先验hash，单目录单文件，目标普通blob再验hash |
| 恶意路径／截断tree／错误镜像 | 报明确数据或完整性失败 | 不执行，不写草稿，不绕开hash或继续浮动main |
| 超大／慢流／取消 | 可取消并及时结束 | 单文件1MiB、总30秒，实际token停止，后续镜像不发起 |
| GitHub限额 | 显示稍后重试及可用重置时间 | 不把429／限额403当无更新，不用旧快照冒充成功 |
| 自定义普通HTTPS源 | 跟随用户导入地址得到候选 | 无upstream字段，只记录content/script hash，inspect由调用方另做 |

本轮不执行以上产品门，不把代码落盘称“已完成所有源更新”或“所有脚本已可用”。

## 本轮交付状态

获取器与本票据已落盘，仅新增这两个文件，未修改既有产品接口。已做人工源码收口：保留自定义地址query、symlink原文不trim以拒绝换行／空白、使用Git对象元数据接口，并复用Dart UTF-8解码器剥离单个BOM。获取器不运行脚本、不inspect、不写草稿或账号数据，也不作许可／平台策略决定。

按本轮约束未运行产品、初始化脚本、测试、analyze、format或构建。公开REST受匿名额度限制，运行时元数据读取、各类下载与错误体验仍属于上表待执行门。没有创建临时验证产物。
