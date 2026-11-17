# 来源与第三方声明

乐音音乐（原名悦音音乐）基于 Mconnect 修改与扩展。

- 上游仓库：https://github.com/Hjdd14/Mconnect-Music_connect
- 对应上游提交：`9df0c0feeb148d65cebe51fea5fe8d4387e16dcc`
- 原版权声明与许可完整保留在 [LICENSE](LICENSE)。
- 新增音源运行时使用的 node-forge 1.3.1 采用其提供的 BSD 许可选项，pako 2.1.0 采用 MIT 许可；两者的完整许可分别保留在 assets/lx-runtime/forge-LICENSE 和 assets/lx-runtime/pako-LICENSE。
- 其他依赖适用各自许可证，依赖版本记录在 pubspec.lock。
- Windows独立音源宿主使用微软Microsoft.Web.WebView2 SDK 1.0.2903.40的Core、WinForms及x64 Loader组件，遵循微软SDK许可；构建时验证微软签名，完整Windows发行包随附该SDK的LICENSE.txt与NOTICE.txt。WebView2浏览器运行时不包含在悦音源码中。详见docs/交付文档/悦音音乐040Windows说明.md。
- QQ音乐、网易云音乐、酷狗音乐图标来自相应厂商官方App Store条目；素材及商标归原权利人，仅用于标识接入平台，MIT代码许可不改变素材权利。原链接、发布者、应用ID及逐字节SHA-256见[平台图标来源](design/platform-icons-010/来源说明.md)。完整Windows包随附同一来源说明。
- 0.5.0应用图标使用用户本轮提供的白底黑白音符飘带图，原参考保留。尺寸导出与未生成透明版本的边界见[图标说明](assets/branding/yueyin/来源说明050.md)。

此仓库的首次提交是整理后的文件快照，未包含本机原 Git 历史；其后持续记录悦音独立入口的功能与文档改动。
