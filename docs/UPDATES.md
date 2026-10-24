# MagicTouch 更新发布

应用通过 Sparkle 2 更新。菜单与设置提供手动检查，自动检查默认关闭，用户可以在设置中开启；安装由用户确认。Debug 构建永远不启动更新器，避免安装正式版本覆盖开发应用。

## 尚未配置发布地址时

无需 GitHub 仓库即可构建和运行。没有有效的 HTTPS 更新地址及 Ed25519 公钥时，更新入口禁用，设置显示“更新暂未开放”。不要发布这样的构建给需要自动升级的用户。

## 首次发布前

1. 创建公开 GitHub 仓库，用 Releases 托管带版本号的 DMG/ZIP。用 GitHub Pages 或自己的域名提供固定 HTTPS `appcast.xml` 地址。
2. 使用已解析的 Sparkle 工具目录：`<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/`。运行 `generate_keys` 一次，将私钥保留在钥匙串并安全备份。不要把私钥、Apple 凭据提交到仓库。
3. 在应用 target 的 Release Build Settings 添加两个 User-Defined 设置（公钥可提交）：
   - `SPARKLE_FEED_URL`：完整 HTTPS 更新清单地址。
   - `SPARKLE_PUBLIC_ED_KEY`：`generate_keys` 输出的 Base64 公钥。
   `Info.plist` 会展开这两个设置。也可在 CI 的 `xcodebuild` 参数中提供它们。
4. 递增 `CURRENT_PROJECT_VERSION`（Sparkle 据此比较版本），设置 `MARKETING_VERSION`，保持正式版 Bundle ID 和签名身份稳定。
5. 使用 Developer ID 签名并公证。Sparkle 官方建议 `xcodebuild archive` 后使用 `xcodebuild -exportArchive` 的 Developer ID 导出流程，确保嵌套的 Sparkle helper 正确签名。随后完成 Apple 公证、staple 和 Gatekeeper 验证。

仓库提供 [Xcode Cloud → GitHub DMG 流水线](RELEASE.md)：Apple 完成 App 签名公证，GitHub 制作未签名的外层 DMG 并上传草稿 Release。使用前需完成后台配置。该流水线不生成或发布 Sparkle appcast；以下更新签名和发布步骤仍需单独完成。

## 每次发布

1. 对完成签名、公证的应用制作 DMG 或 ZIP，放入更新归档目录。保留历史归档。
2. 使用 Sparkle 的 `generate_appcast` 生成带 EdDSA 签名的清单；执行 `generate_appcast --help` 查看 `--download-url-prefix` 等选项。下载链接必须指向具体版本的 GitHub Release 附件，不能指向变化的 `latest` 文件。
3. 可以将同名 HTML 或 Markdown 文件放在归档旁，作为版本说明。确保生成的说明链接也实际可访问。
4. 先上传安装包、版本说明及生成的增量包（若有），验证附件可下载，再发布更新清单。不要在签名后重新打包或修改归档。
5. 从旧的已签名、公证版本实际升级，验证版本变更、重启、辅助功能权限、开机启动与鼠标监听。还需验证取消更新、网络失败、无新版与无效签名不会破坏现有安装。

官网可直接链接 GitHub Release。更新清单使用自有域名有助于日后迁移下载服务；无需在客户端放 GitHub Token。

官方文档：https://sparkle-project.org/documentation/
