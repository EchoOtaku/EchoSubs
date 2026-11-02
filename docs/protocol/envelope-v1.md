# EchoSubs 加密协议 v1

本协议仅保护传输/备份对象和恢复主密钥，不代表本地 SQLite 已加密。实现使用 cryptography 2.9.0 的 AES-256-GCM 与 HKDF-SHA256；不接收口令作为恢复秘密。下列向量全部为公开、虚构测试数据，禁止作为实际密钥。

## 编码与限制

对象为严格 UTF-8（无 BOM）的规范 JSON。所有对象键按 UTF-16 code unit 字典序递归排序；数组保留顺序；不允许空白、重复键、未知字段或任何非规范表示。字符串使用 Dart `jsonEncode` 的 JSON 转义：双引号/反斜杠转义、常用控制字符使用短转义、其他控制字符使用小写 `\u00xx`，其他 Unicode 字符直接使用 UTF-8；不转义 `/`，不做 Unicode 归一化；拒绝未配对 surrogate。只有 signed-int64 整数、字符串、布尔、null、数组、对象，禁止浮点/指数数字和负零。解析后规范重编码必须逐字匹配原文，故重复键即使值相同也被拒绝。嵌套最多 64 层。

对象的完整编码（含 base64 膨胀）最多 1,048,576 字节；解密正文也最多此大小。每个 `notes` 的 UTF-8 字节最多 16,384（含边界）。调用者应在读取网络/文件流时同样执行上限，不能先无限缓冲再交给 codec。二进制均为标准 RFC4648 base64，带必要 `=` padding，禁止空白、URL alphabet 和非规范 pad bits。ID 为 32 位小写十六进制。

## 同步/备份信封

恰好八个字段：`version`（整数 1）、`purpose`（`sync` 或 `backup`）、`ledgerId`、`batchId`、`salt`（32 bytes）、`nonce`（12 bytes）、`ciphertext`（非空）、`tag`（16 bytes）。使用 AES-256-GCM，tag 为完整 128 位。每次 seal 独立生成安全随机 salt 和 nonce，主密钥为 32 bytes。同步与备份各用 `EnvelopeCodec(purpose: ...)`，默认 sync；codec 拒绝其他用途，包括另一个已知用途。

正文为 `ChangeBatch.toJson()` 的规范 JSON，包括完整 mutations。解密成功之前不解析任何业务字段；之后校验领域模型、正文 ID 与认证头一致、模型重新编码完全相同，拒绝未知字段、重复 parent、重复 mutation 和可被模型归一化的日期/顺序。

HKDF 输入：IKM = 32-byte ledger root；salt = 信封 salt；Hash = SHA256；L = 32。HKDF info 为以下数组的规范 JSON UTF-8 **原始字节**，无换行、无终止零：

```json
["EchoSubs",1,"sync","11111111111111111111111111111111"]
```

实际替换 purpose 和 ledgerId。AAD 是以下数组的规范 JSON UTF-8 原始字节：

```json
["EchoSubs",1,"sync","11111111111111111111111111111111","22222222222222222222222222222222"]
```

此处数组元素顺序固定为域分隔常量、version、purpose、ledgerId、batchId。salt 参与派生、nonce 参与 GCM，均不能替换后通过认证。没有额外拼接、长度前缀或摘要。加密算法与 KDF 在 v1 中固定，不接受算法协商/降级。

同一 batch 只 seal 一次后持久化**原始 bytes**供重试及两通道复用。seal 是无状态函数；再次调用会产生另一组合法 bytes，不会修改 batch/keys 或先前 bytes，调用者不能以重新 seal 代替读取已有不可变对象。不要以信封密文随机性判断业务 batch 是否相同。

## 恢复元数据

恰好八个字段：`version:1`、`purpose:"wrapping"`、`ledgerId`、`batchId:""`、`salt`（32 bytes）、`nonce`（12 bytes）、`wrappedRoot`（32 bytes）、`tag`（16 bytes）。`LedgerMetadata.id` 对应 JSON ledgerId。元数据不包含恢复秘密或明文主密钥。封装 plaintext 是主密钥原始 32 bytes，不是 JSON/base64 字符串。

`RecoveryCode.generate()` 使用系统安全随机源生成 32 bytes，编码为 `ES1-` + 无 padding 的 base64url（43 个字符），总长 47。parse 仅用于导入此格式，不提供口令派生或“自设恢复密码”；格式校验无法证明用户手工输入字符串的熵，产品只能生成随机恢复码。恢复秘密与主密钥独立生成。

wrapping HKDF 的 IKM 为恢复秘密原始 32 bytes，salt 为元数据 salt，info 是 `["EchoSubs",1,"wrapping",ledgerId]` 的规范 UTF-8；AAD 是 `["EchoSubs",1,"wrapping",ledgerId,""]` 的规范 UTF-8。nonce/tag 与同步规格相同。随机 salt 确保重复包装独立；原元数据可持久化并重复恢复，不是一次性令牌。

`createLedgerBundle(id)` 返回 keys、metadata、recovery；keys 不序列化进入传输对象。`LedgerMetadata.encode/decode` 保存/读取严格 bytes，`toJson/fromJson` 供可信持久化集成。后者的 Map 已丢失原始表示，不能代替入站 bytes 的严格 decode。

## 安全存储与错误

KeyVault 的底层可注入 `VaultStorage`，真实实现 `SecureVaultStorage` 使用 flutter_secure_storage 11.2.0；平台真实读写门槛在任务 11。本任务仅使用 fake。名字限制为 `[A-Za-z0-9_.-]{1,128}`，底层加 `echosubs.v1.` 前缀，非空 secret 上限 4096 bytes，以规范 base64 存储。读到缺失返回 null，读到不可用或损坏值抛 locked；写入失败抛 unavailable。上层遇到 null/locked 必须保持原账本并引导解锁，不能自动替换密钥或清空数据库。

未知整数版本/用途：incompatible；格式/容量/正文不一致：validation；密文认证失败/错误账本：integrity；错误恢复秘密或包装认证失败：locked。错误只有固定安全消息，不拼接原始异常、载荷、名称或秘密；无秘密日志。内存防御性复制避免外部修改，但不宣称 Dart GC 内存可可靠清零。

## 固定虚构互通向量

root = bytes 0..31；salt = bytes 64..95；nonce = bytes 96..107（均按十进制连续值）；purpose = sync。ledgerId 为 32 个 `1`，batchId 为 32 个 `2`，deviceId 为 32 个 `3`，category ID 为 32 个 `4`。

plaintext（单行 UTF-8，无换行）：

```json
{"createdAtUtc":"2026-01-01T00:00:00.000Z","deviceId":"33333333333333333333333333333333","id":"22222222222222222222222222222222","ledgerId":"11111111111111111111111111111111","mutations":[{"parentBatchIds":[],"ref":{"id":"44444444444444444444444444444444","kind":"category"},"value":{"id":"44444444444444444444444444444444","name":"fictional-private-name"}}]}
```

derived AES key（base64）：`lfQt/d8trCf72D9ClOpDZESRF19gT5Q264yW6PZlk+Y=`

tag（base64）：`lqWtw78WCysg+I4k19ZNwA==`

ciphertext（base64，单行）：

```text
WcqMKM5EOlqA1OCVMoQjJYDXIZzzh9k3ipeBKKJ4x/8MQHtMKr63cJB/+tVCNfGTce4gz/8+jKbzdIiK09pYhLN71uDbtf6OJji1LY8Mi5r0FW37bqqI6tE5wXeBuG0z7ccLAJBfJd60EH3wuRuTdTlbKtacBH7x9arv85EN04pswJy2pKrIqCoBh02UXuDqL+6rWlaCHmoJv2lg1DBchnaIZnP0Ep++baVdd1s/4EkJ2HUyJWNWQDpTvhIjGR50eu1sMtNCEhmxFeqgVoFN0BwVoH3jjiffQ4dDx8BcYhFjv+ZGRkqLQu5ttXyA5NCKsPNKtV42FC9NjqKYu7HLfXcsX8dEh52eFiuMnCLaDGVfPZ54eVl4Ahefz5ITEjtgv3lrbKHR1/eny49K+r6eDXGT01NmV46GQe2+hj0iBrroqdn2YrLnefo2kE0QVfjxhzl16whBdudVmctEMfIWTPVlbsajYoM=
```

`test/crypto/envelope_test.dart` 固定断言此 key/ciphertext/tag，并以完整规范信封 open 回原始批次。向量固定 salt/nonce 仅用于互操作测试，生产路径不能注入固定随机数。
