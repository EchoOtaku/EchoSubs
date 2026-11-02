# 发布内容与隐私核查

## 范围

2026-11-02 对首版界面版本 `1.0.0+2` 进行发布核查，应用源码为 `b350468`。此次补齐中英 README 与维护文档，不修改应用、协议或构建配置；安装包继续使用已完成原生验收的相同二进制。

核查包含当前版本控制文件与未忽略的新文档、所有本地 Git 对象和历史文件名、远端分支同步、GitHub issue/PR 正文及评论，以及待发布 Windows ZIP/APK 的每个成员和解压后的许可证文本。没有读取被忽略的真实账本、操作系统凭据库、恢复密钥或仓库外的私人目录。

仓库继续保持私有；提交作者信息经所有者明确确认保留。本次没有改写历史或更改访问权限。

## 方法与结果

- 使用现有 Git/Python，检查常见云服务/API 凭据格式、私钥标记、含凭据 URL、字面量凭据、异常高熵内容、个人用户目录及敏感文件名；候选只按规则与位置记录，不打印匹配值。
- 初次覆盖 30 个提交、339 个历史文件对象、169 个当前文件；11 项忽略规则探针全部命中。GitHub 文本覆盖两个 PR，无 issue 评论或行内评论。
- Windows ZIP 的 19 个成员和 APK 的 342 个成员未发现数据库、恢复密钥文件、签名私钥、私人导出、日志或调试转储。APK 中的签名证书是公开证书，不是签名私钥。
- 8 次高熵命中来自协议文档及测试中相同的合成向量，种子、salt、nonce 均由公开确定序列生成；4 次私钥标记命中为四个架构快照中的 RSA PEM 格式字符串，没有连续私钥载荷，源码确认设备身份在运行时生成并写入 OS Vault。没有将规则命中自动当作真实泄漏或直接删除。
- 解压许可证文本后的另 2 次高熵命中为上游 ICU 词典的公开许可证 URL；第三方许可证中的作者邮箱属于正常许可信息，未将其当作用户私人内容删除。14 类检测器合成自检和文档相对链接检查通过。
- 安装包保留项目构建目录的技术元数据；未发现个人用户目录或私人文件内容。此核查不宣称二进制完全匿名。历史文档中的非机密项目路径仍留在历史中，当前文档已改为通用说明。
- 从应用入口计算引用关系，所有 `lib` 源文件均可达；没有发现可确认废弃的游离生产源码。平台模板、生成代码、测试支持文件仍有用途。旧设计/计划标记为历史归档，旧“空壳”状态和协议阶段说明已修正，没有批量删除文件。

原始扫描、逐项复核和文件清单位于本机忽略目录。发布附件仅包含经过校验的安装包、摘要与不含本机路径/凭据值的发布清单和审查摘要。

## 边界

这是一轮有范围的内容审查，不是渗透测试，也不是“绝无任何泄漏”的形式化证明。模式与熵检测存在遗漏和误报；二进制依赖保留正常的上游许可证与构建元数据。操作系统账户、磁盘、WebDAV 服务及用户之后录入的数据不在这次仓库审查范围内。

加密同步和加密备份不代表本地 SQLite 全库加密。当前 APK 仍使用本机测试签名，生产签名与已有 [验收边界](../build/acceptance.md) 不因发布而改变。

## English summary

The release audit covers current version-controlled files, Git objects/history, GitHub issue/PR text and comments, and all members of the Windows ZIP and Android APK, including decompressed notices. The repository remains private; the owner explicitly chose to retain Git author identity.

Reviewed matches are deterministic synthetic interoperability vectors and RSA PEM formatting markers used by runtime-generated device identities. No actual API credentials, private-key payloads, personal databases, exports, or logs were identified within this scope. All production Dart source files are reachable from the app entry point; historical design/plan documents are explicitly archived.

Project build-path metadata and ordinary upstream license information can remain in binaries. This is a scoped review, not a proof of complete anonymity or absence of every possible disclosure. Local SQLite is not fully encrypted, and the APK still uses a local test certificate.
