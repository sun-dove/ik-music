# DJ Music

顶尖（Dingjian）是 GitHub 项目的归属名称；面向用户的产品在 Windows、Android 和应用内统一叫 **DJ Music**。DJ Music 支持 QQ 音乐、网易云与酷狗音乐接入，提供账号收藏、多音源管理和灵活的播放设置。

当前公开发行版仍为 **0.5.0**。下一兼容版 **0.5.1 / build 9** 的候选安装包已构建，采用 DJ Music 名称和新版图标；它尚未发布。Windows CI、安装覆盖与品牌界面已验收，Android 三 ABI 已构建并核验签名，详见[0.5.1 候选验收记录](docs/交付文档/DJ-Music-051候选验收记录.md)。历史 0.5.0 的下载、验收和发行标签继续保留：[0.5.0 发行页](https://github.com/sun-dove/yueyin-music/releases/tag/yueyin-v0.5.0)、[0.5.0 验收记录](docs/交付文档/乐音音乐050验收记录.md)。更新版沿用原包名、签名、安装身份与数据目录。

<img src="assets/branding/dj-music/source/windows/yangyin-256.png" width="100" alt="DJ Music 渐变音符图标">

## 功能

- **账号与收藏**：QQ、网易云及酷狗入口；酷狗增加歌单浏览，分页失败保留已获取内容并明确提示未完整。
- **自定义音源**：通过 HTTPS 链接导入兼容的洛雪音源脚本。
- **多音源管理**：保存多个音源，支持更新、排序、设为首选、启停和删除。
- **列表检查**：名称和平台筛选、紧凑列表、固定保存按钮、完整筛选结果逐项检查与取消；失败保留草稿。
- **自动切换**：启用后，取流或播放失败时自动尝试其他可用音源。
- **音质优先**：优先尝试最高可用音质，并显示降档与来源信息。
- **播放详情**：查看尝试记录、失败原因和未试音源，达到单轮等待上限后可继续尝试。
- **Windows 两项音质**：统一播放音质与下载音质，旧各平台设置保留，暂停续传保持原档。
- **Windows 个性化**：预览和保存本机背景，选择实际安装的字体或导入 TTF/OTF，使用三平台真实图标。
- **Windows 完整歌词**：宽屏左封面、右歌词，支持同步跟随、手动浏览和恢复。
- **Windows 关闭设置**：默认最小化并继续播放，也可设置真正退出，提供独立退出入口。

## 安装

按系统和设备架构选择：

| 安装包 | 适用设备 |
| --- | --- |
| [Android arm64-v8a](https://github.com/sun-dove/yueyin-music/releases/download/yueyin-v0.5.0/YueyinMusic-0.5.0-arm64-v8a.apk) | 大多数安卓手机，推荐 |
| [Android armeabi-v7a](https://github.com/sun-dove/yueyin-music/releases/download/yueyin-v0.5.0/YueyinMusic-0.5.0-armeabi-v7a.apk) | 支持的旧款 32 位设备 |
| [Android x86_64](https://github.com/sun-dove/yueyin-music/releases/download/yueyin-v0.5.0/YueyinMusic-0.5.0-x86_64.apk) | x86_64 安卓模拟器或设备 |
| [Windows x64 安装器](https://github.com/sun-dove/yueyin-music/releases/download/yueyin-v0.5.0/YueyinMusic-Setup-0.5.0-x64.exe) | Windows 10/11，可选择安装目录 |
| [Windows x64 免安装 ZIP](https://github.com/sun-dove/yueyin-music/releases/download/yueyin-v0.5.0/YueyinMusic-0.5.0-windows-x64.zip) | 完整解压后运行 yueyin_music.exe |

文件校验值见发行页的 [SHA256SUMS](https://github.com/sun-dove/yueyin-music/releases/download/yueyin-v0.5.0/SHA256SUMS)。Windows 完整包包含 EXE、DLL、data 与运行时许可，详见[Windows 说明](docs/交付文档/乐音音乐050Windows说明.md)。iOS 和 Linux 图标资源为平台适配源文件，本仓库没有对应的发行构建和安装包。

## 使用音源

1. 打开“我的 → 自定义音源 → 多音源管理”。
2. 粘贴具体的 HTTPS 脚本链接，点击“从链接导入”。
3. 启用需要的音源，设置首选和尝试顺序。新导入的音源默认关闭。
4. 点击“使用推荐设置”，开启音源优先、失败自动切换和最高可用音质。
5. 点击“保存设置”后开始播放，也可按自己的偏好调整这些选项。

最高可用模式会先尝试各音源的高音质，再逐档降低。实际可用音质取决于歌曲和音源返回的资源；请求档位与音频实际音质分别显示。

新版列表将低频操作放进每条音源的“更多”菜单。返回时可保存、放弃或继续编辑；筛选仅改变显示，不修改实际播放顺序。旧版操作背景见[使用说明](docs/交付文档/悦音音乐033使用说明.md)。

## 兼容范围与问题反馈

音源导入成功不等于每首歌曲都能播放。0.4.0 的固定版本全部20个入口已完整诊断：移动协议主机18个初始化、17个声明支持平台；Windows真实宿主17个初始化、16个声明支持平台。平台范围、各源失败及完整SHA-256见[历史兼容矩阵](docs/交付文档/悦音音乐040音源兼容矩阵.md)。本版不修改播放算法，真实账号、完整歌曲播放与音质按[本版验收记录](docs/交付文档/乐音音乐050验收记录.md)说明，未用历史初始化结果替代实测。

反馈问题时，请提供应用版本、设备系统、音源名称及版本、歌曲与歌手、操作步骤和页面错误提示。请勿附带账号 Cookie、访问令牌或签名口令。

## 开发

项目使用 Flutter，乐音音乐入口为 `lib/main_video.dart`，相关界面与兼容层位于 `lib/video_app/`，Windows 扩展位于 `lib/video_app/windows/`。

环境配置、测试、自有签名及 APK 分包步骤见[开发与构建](docs/交付文档/悦音音乐开发与构建.md)。

## 开源说明

乐音音乐基于 Mconnect 修改与扩展，保留上游版权声明和 [MIT 许可证](LICENSE)。第三方组件与平台图标遵循各自许可和权利声明，详情见 [NOTICE](NOTICE.md)。

项目提供播放器与音源接入功能，不附带音乐文件或第三方音源脚本。
