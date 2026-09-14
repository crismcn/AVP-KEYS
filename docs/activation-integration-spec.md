# AVP KEYS 激活密钥 · 新应用接入开发规范

版本：v1.0（2026-09-14）
适用：任何需要「离线激活授权」的新客户端（Flutter / Android / iOS / 桌面 / Web）
签发侧参考实现：本仓库 `lib/src/crypto/ed25519_service.dart`

---

## 0. 术语与职责边界

| 术语 | 含义 |
| --- | --- |
| 签发侧 | 「AVP KEYS」密钥生成器（本仓库 App / `tools/keygen.html`），持有**私钥**，负责签发密钥串 |
| 接入侧 | 要接入激活的新应用，只持有**公钥**，负责离线验签与授权状态管理 |
| 密钥串 / token | 签发给终端用户的那串 170 位大写 hex，用户粘贴进接入侧完成激活 |
| 激活窗口 | `[激活开始, 激活截止]`，只有落在这段时间内的**首次**激活才被接受 |
| 授权截止 | 激活成功后授权可用的最后时刻；到点后应用锁定 |

核心约定：**签发侧与接入侧零网络交互**。授权凭证自带全部信息（时间 + 签名），接入侧只需一把内嵌公钥即可完成校验。

> ⚠️ **每个接入应用应使用独立的密钥对**。当前 v1 的 claims 里没有应用标识字段，同一把公钥签出的密钥串在任意接入侧都可通过校验。若多个应用共用一对密钥，一旦某应用被逆向、公钥被替换或被伪造签发，影响面会扩散到所有应用。**新应用接入时请单独生成一对密钥**（操作见 §9）。

---

## 1. 密码学算法

| 项 | 规定 |
| --- | --- |
| 签名算法 | Ed25519（RFC 8032），纯离线 |
| 签名对象 | claims 的 **21 字节原始字节**（不是 hex 字符串，不要做任何二次编码） |
| 签名长度 | 64 字节 |
| 公钥 | 32 字节，hex 表示 **小写 64 字符** |
| 私钥 | 32 字节 seed，PKCS8 DER（RFC 8410）base64 —— **仅签发侧持有，禁止出现在接入侧仓库/包里** |
| 编码 | 密钥串 = `21B claims ‖ 64B 签名` 整体 hex，**大写，无分隔符，共 170 字符（85 字节）** |

推荐实现（各平台均为成熟标准库，不要自行实现 Ed25519）：

| 平台 | 推荐库 |
| --- | --- |
| Flutter / Dart | `cryptography: ^2.7.0` 的 `Ed25519()`（与签发侧同库，最稳） |
| Android / JVM | `net.i2p.crypto:eddsa`、BouncyCastle `Ed25519Signer`、JDK 15+ `Ed25519` |
| iOS / macOS | CryptoKit `Curve25519.Signing` |
| Web / Node | WebCrypto `Ed25519`（`crypto.subtle.verify('Ed25519', …)`）/ libsodium |
| C# | `NSec`、libsodium-net |

关于验签严格性：签发侧不产生非规范编码（S 的高位、小阶公钥等都取标准值），因此各库互通无碍；但接入侧建议开启严格校验（例如额外的 `S < L` 检查），以提高抗伪造裕度。

---

## 2. 密钥串格式规范

### 2.1 字节布局（85 字节）

| 偏移 | 长度 | 字段 | 编码 | 说明 |
| --- | --- | --- | --- | --- |
| 0 | 1 | version | uint8 | 固定 `0x01`。其它值一律拒绝 |
| 1 | 4 | activationStart | uint32 **大端** | 激活开始，UTC 纪元秒 |
| 5 | 4 | activationEnd | uint32 **大端** | 激活截止，UTC 纪元秒 |
| 9 | 4 | expiry | uint32 **大端** | 授权截止，UTC 纪元秒 |
| 13 | 8 | nonce | 随机字节 | 同一时间窗口下每枚密钥唯一；也用于向销售台账溯源 |
| 21 | 64 | signature | Ed25519 | 对**前 21 字节**的签名 |

约束：

- 所有时间为 **UTC 纪元秒**（`DateTime.now().millisecondsSinceEpoch ~/ 1000`），**与设备时区无关**。展示时再转本地时间。
- 时间字段为 uint32，取值上限 `0xFFFFFFFF`（2106-02-07）。签发侧已做该校验，接入侧解析按无符号处理即可。
- 时间关系恒满足 `activationStart < activationEnd ≤ expiry`（签发侧 `validateTimes` 保证）。
- 密钥串全局唯一：`version + 三个时间` 相同的一批密钥，靠 8 字节 nonce 区分。接入侧**不要**用「前 13 字节」做去重键。

### 2.2 输入归一化（必做）

用户在 App 里粘贴的内容是**脏的**，实际情况包括但不限于：

- 带前缀：签发侧「复制密钥」按钮写入剪贴板的内容是 `激活密钥：<170hex>`；
- 带分组连字符：UI 展示形态为每 4 位一个 `-`（`ABCD-EF01-…`，末组 2 位）；
- 跨行、带空格、带换行（从 Markdown 台账表格里整行复制）；
- 小写 hex；
- 尾部混入说明文字。

归一化规则（按序执行）：

1. 删除所有空白字符与 `-`、`–`、`—` 等分隔符；
2. 在结果中匹配**第一段连续 170 位 hex**：正则 `[0-9A-Fa-f]{170}`；
3. 统一转大写。

匹配不到 170 位连续 hex → 判为格式错误。

> 不要在归一化时做「去掉所有非 hex 字符」的操作——中文前缀会被直接删掉看似没问题，但遇到含数字字母的说明文字（如「订单 2026」）会拼接出错误串。用「找一段连续 170 位」的正则更安全。

---

## 3. 校验算法

### 3.1 伪代码

```
verify(rawInput, now, alreadyActivated):
  hex   = normalize(rawInput)                    # §2.2
  if hex == null:                 return FORMAT
  bytes = hexDecode(hex)                         # 必为 85 字节
  if bytes[0] != 0x01:            return VERSION
  claims  = bytes[0..21]
  sig     = bytes[21..85]
  if !ed25519Verify(sig, claims, publicKey):     return SIGNATURE     # ① 签名必须在时间判定之前
  c = parse(claims)                              # 三个 uint32 大端 + nonce

  if alreadyActivated:                           # 复检已激活的授权（启动/长会话）
      if now > c.expiry + SKEW:   return EXPIRED
      return OK

  if now < c.activationStart - SKEW: return NOT_STARTED
  if now > c.activationEnd   + SKEW: return WINDOW_CLOSED
  if now > c.expiry          + SKEW: return EXPIRED
  return OK
```

**判定顺序不可调换**：签名必须最先校验。否则伪造者可以随意编造时间字段，诱导用户看到「激活窗口已关闭，请联系客服」之类的文案，形成误导性客诉。

### 3.2 时钟偏移容差

`SKEW = 300` 秒（5 分钟）。原因：`activationStart` 取自**销售方设备**的时钟，而 `activationEnd` 与 20 分钟的激活窗口非常短，买卖双方设备时钟若有几分钟偏差，会出现「刚生成的密钥提示尚未开始 / 已过期」。两侧（开始与结束）都要放宽 `SKEW`。

这是可用性与安全性的显式取舍：放宽 5 分钟意味着最多 5 分钟的越界可用。若业务不接受，把 `SKEW` 改小（如 60 秒），但必须在接入侧的配置常量里集中定义，不要散落在多处。

### 3.3 结果与文案对照表

| 结果 | 触发条件 | 用户可见文案（建议） | 是否允许重试 |
| --- | --- | --- | --- |
| `FORMAT` | 归一化失败 / 长度不等于 85B | 密钥格式不正确，请完整复制 170 位密钥后重试 | 是 |
| `VERSION` | version ≠ 0x01 | 密钥版本不受支持，请升级到最新版本后重试 | 是（升级后） |
| `SIGNATURE` | 验签失败 | 密钥无效，请核对后重试；如确认无误请联系客服 | 是 |
| `NOT_STARTED` | `now < activationStart - SKEW` | 激活尚未开始，请在 {本地时间} 之后重试 | 是 |
| `WINDOW_CLOSED` | `now > activationEnd + SKEW` 且未激活 | 激活窗口已关闭（有效期至 {本地时间}），请联系客服重新获取 | 否 |
| `EXPIRED` | `now > expiry + SKEW` 且已激活 | 授权已到期，请续期后继续使用 | 否 |

文案中一律把纪元秒转成**本地时间**再展示（含时区标注更佳，签发侧台账用的就是本地时间）。

---

## 4. 激活状态机与本地持久化

### 4.1 状态

```
未激活 ──首次激活成功──▶ 已激活 ──now > expiry──▶ 已过期
```

- **激活（redeem）只在激活窗口内发生一次**。窗口关闭后不可再激活——这是「限时交付」的产品约束，不是 bug。
- 已激活的授权**不受激活窗口关闭影响**，一直有效到 `expiry`。`activationEnd` 与 `expiry` 是两个独立概念，切勿混用。

### 4.2 推荐存储方案

**只持久化 token 本身 + 单调时钟水位**，不要持久化解析后的 `expiry`、`activationStart` 等派生值：

```
key:   avp_license_token     value: <170 位大写 hex>
key:   avp_last_seen_epoch   value: <uint32 字符串，单调递增>
```

理由：派生值一旦落盘就成了可篡改的信任源（改一下本地存的 `expiry` 就白用一年）。每次启动重新验签 + 重新解析，篡改 token 必然导致验签失败，攻击面只剩「时间水位」一处需要额外保护。

验签耗时在毫秒级，冷启动重新验签完全可接受；放在启动闪屏期间同步完成，避免首屏授权状态闪烁。

### 4.3 校验时机

| 时机 | 动作 |
| --- | --- |
| 冷启动 | 读 token → 验签 → 按 §3.1 `alreadyActivated=true` 分支判定 |
| 进入受限功能前（如开始录制） | 复检一次 |
| 长会话（连续录制 > 1 小时） | 每 60 分钟复检一次，防止跨过 `expiry` 边界继续使用 |
| 用户手动输入密钥 | §3.1 `alreadyActivated=false` 分支 |

### 4.4 时钟回拨防护

离线授权的固有弱点：用户把系统时间往回拨就能续命。可落地的对策（按性价比排序）：

1. **单调水位**（必做）：每次校验通过后写 `last_seen = max(last_seen, now)`；校验时用
   `effectiveNow = max(now, last_seen)`。这样「把时间拨回去」不会让授权变长。
2. **回拨检测**（建议）：若 `now < last_seen - SKEW`，判定系统时间被回拨。此时用 `last_seen` 继续计时（不要直接锁死——用户换时区、网络对时都可能造成小幅回退）。
3. **第二时间源**（可选）：Android 用 `SystemClock.elapsedRealtime()`、iOS 用 `mach_continuous_time`，与墙钟一起推进水位；App 只要不重启、不回滚安装，就用单调时钟兜底。
4. **存储保护**（建议）：`last_seen` 与 `token` 存入平台安全存储（Android Keystore / `EncryptedSharedPreferences`、iOS Keychain、Windows DPAPI、macOS Keychain）。

   > 注意：Android Keystore 能防「读」，但不能防「root 后改」。若要让水位不可改，需在写入时附带 `HMAC-SHA256(k_store, token ‖ last_seen)`，`k_store` 为设备绑定、不可导出的 Keystore 密钥；读取时先验 HMAC 再使用。是否值得做，取决于你的目标攻击者等级（普通用户 / 逆向者）。

### 4.5 安全存储实现要求

- 不得把 token 明文写进 `SharedPreferences` / `NSUserDefaults` / 日志 / 崩溃上报 / 分析埋点。日志里最多打后 6 位作为订单标识。
- 不得在 UI 上回显完整 token（激活成功后可显示后 6 位，方便客服对账）。
- 卸载重装后授权丢失是**预期行为**（离线授权没有服务端账号体系），产品文案需要明确告知，避免客诉。

---

## 5. 公钥接入方式

公钥不是秘密，可以内嵌进客户端、可以进版本库。要求：

1. **以常量清单形式内嵌**，支持多把并存。这样将来换密钥时，老用户手上的存量密钥仍然有效（续期、换机后重新激活都能过）。
2. 验签时**逐把尝试**，全部失败才返回 `SIGNATURE`。
3. 记录命中的是哪一把（可选，用于灰度下线旧密钥）。

Flutter 参考（与签发侧 README 的路径约定一致）：

```dart
// lib/features/activation/activation_public.dart
//
// 把签发侧「1 · 密钥对」里复制的【公钥 (hex)】粘到这里（小写 64 位 hex）。
// 新增公钥请**追加**，不要删除历史公钥。
const List<String> kActivationPublicHex = <String>[
  'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', // 示例，替换成真实公钥
];
```

> 上面那串是 RFC 8032 TEST 1 的公钥，**只能用于单元测试**，上线前务必替换。生产公钥由签发侧生成后通过安全渠道交付（见 §9）。

其他语言：Kotlin `val ACTIVATION_PUBLIC_HEX = listOf("…")`；Swift `let activationPublicKeys: [String] = […]`；均按同样的「清单 + 逐把尝试」语义实现。

---

## 6. UI / UX 规范

| 项 | 要求 |
| --- | --- |
| 输入控件 | 单行多行均可，但必须：自动去空格、粘贴即触发归一化、允许一次性粘贴带前缀的整段文本 |
| 分组展示 | 展示时按每 4 位插入 `-`（与签发侧 `formatKey` 一致，末组 2 位），**提交前必须去掉分隔符** |
| 输入中提示 | 边输入边显示已识别到的位数（`78 / 170`），归零时提示「密钥应为 170 位十六进制字符」 |
| 提交反馈 | 校验在客户端同步完成（毫秒级），成功即进入已激活态；失败按 §3.3 给出**具体**原因，不要统一提示「密钥错误」 |
| 剩余时间 | 已激活态展示「授权剩余 X 天 Y 小时」（本地时间），到期前 7 / 3 / 1 天做一次温和提醒（可选） |
| 到期行为 | 到期时弹框说明并**停止受限功能**（如停止录制）。已录制的历史数据**不得删除**，用户应仍能查看/导出——这是产品决策点，见 §11 |
| 剪贴板 | 支持「从剪贴板粘贴」按钮，降低手输错漏 |

---

## 7. 安全要求与威胁模型

**这套方案能防**：伪造密钥（无签名者无法构造有效密钥串）、篡改授权时间（时间字段在签名覆盖范围内）、离线环境下的授权校验。

**这套方案防不住**（必须知情并写进产品预期）：

| 攻击 | 说明 | 缓解 |
| --- | --- | --- |
| 密钥外传 | 一枚密钥在窗口内可被无限台设备激活 | claims 无设备/账号绑定字段；靠短激活窗口（默认 20 分钟）+ 8 字节 nonce 溯源台账。若业务要求强绑定，需要服务端参与，超出 v1 范围 |
| 撤销 | 无法作废已签发且已激活的密钥（无 CRL/OCSP，纯离线） | 只能靠短授权周期实现自然过期 |
| 客户端补丁 | 逆向者 patch 掉校验分支 | 属通用问题；可做代码混淆/完整性校验，但无法根除。授权方案的目标是提高门槛，不是绝对防护 |
| 系统时间篡改 | 拨慢时钟延长授权 | §4.4 的单调水位 + 回拨检测 |

**接入侧红线**：

- 私钥永远不进接入侧仓库、不进客户端产物、不进 CI 变量以外的任何位置；
- 不实现「本地签发/自签」能力（即接入侧不含 PKCS8 解析与签名代码），只做验签；
- 不为了「调试方便」加一个跳过验签的开关并合进发布分支。

---

## 8. 测试与验收

### 8.1 密码学自检（必做，不依赖任何外部数据）

把 RFC 8032 的标准向量写进接入侧测试，确认所用 Ed25519 实现正确：

```
# TEST 1（空消息）
seed     = 9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60
public   = d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a
message  = (空)
signature= e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155
           5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b

# TEST 2（单字节消息 0x72）
seed     = 4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb
public   = 3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c
message  = 72
signature= 92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da
           085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00
```

（seed 均为 64 位 hex = 32 字节；写进代码时请每 2 位拆成一个字节，勿把空格或分组符混入字节数组。这两组向量与本仓库 `test/crypto_vectors_test.dart` 中的完全一致。）

### 8.2 字节级往返（必做）

用 TEST 1 的 seed 组装 PKCS8（RFC 8410 固定头 `302e020100300506032b657004220420` ‖ seed），在**签发侧**用固定窗口签一枚，把结果作为黄金样本固化进接入侧测试：

| 输入 | 值 |
| --- | --- |
| 私钥 PKCS8（hex） | `302e020100300506032b657004220420` ‖ `9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60` |
| 公钥（hex） | `d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a` |
| activationStart | `1704038400`（hex `65919000`） |
| activationEnd | `1704039000`（hex `65919258`） |
| expiry | `1704067800`（hex `659202D8`） |
| nonce | `0000000000000000`（测试用固定值） |
| 期望 claims（hex） | `01` `65919000` `65919258` `659202D8` `0000000000000000` = 42 位 |
| 期望密钥串 | `01 65919000 65919258 659202D8 0000000000000000` ‖ `⟨64B 签名⟩`，共 170 位大写 hex |

操作步骤：签发侧导入上述 PKCS8 私钥（若工具不接受手改的 PKCS8，可先按 `pkcs8SeedFromB64` 的规则生成 base64 文本再导入）→ 手动设置窗口为固定值 → 点一次「生成密钥」→ 把得到的 170 位串粘贴为接入侧测试常量。**签发侧与接入侧各存一份该黄金向量**，将来任一侧改了格式，测试会立刻红。

说明：Ed25519 是确定性签名，固定私钥 + 固定 21 字节 claims ⇒ 签名唯一，因此这个向量可以长期稳定复用（唯一变量是 nonce，测试时须固定为 0）。

### 8.3 边界用例表（必做）

| # | 场景 | 期望 |
| --- | --- | --- |
| 1 | `now == activationStart` | OK |
| 2 | `now == activationEnd` | OK（边界含端点） |
| 3 | `now == activationEnd + 301`，未激活 | `WINDOW_CLOSED` |
| 4 | `now == activationStart - 301` | `NOT_STARTED` |
| 5 | 已激活，`now == expiry` | OK |
| 6 | 已激活，`now == expiry + 301` | `EXPIRED` |
| 7 | 已激活，`now` 在 `[activationEnd, expiry]` 之间 | OK（窗口关闭不影响已激活授权） |
| 8 | 输入带 `激活密钥：` 前缀 | OK |
| 9 | 输入带 `-` 分组（每 4 位） | OK |
| 10 | 输入小写 hex | OK |
| 11 | 输入 169 / 171 位 | `FORMAT` |
| 12 | 改动密钥串任意 1 个 hex 字符 | `SIGNATURE` |
| 13 | version 改为 `0x02`（其余不动） | `VERSION`（且**不得**因验签失败而先报 `SIGNATURE`——版本判定在验签前，两者都拒绝即可，但文案须为版本类） |
| 14 | 空串 / 纯中文 / 纯符号 | `FORMAT` |
| 15 | 篡改本地存储的 token | 启动后回到未激活态，不崩溃 |
| 16 | `last_seen` 未来值 + 系统时间回拨 | 以 `last_seen` 计时，不延长授权 |

### 8.4 与签发侧联调验收

1. 接入侧把生产公钥拿到手（§9），确认与签发侧界面显示的「公钥 (hex)」逐字符一致；
2. 签发侧按真实业务档位（如「1 小时」）签一枚，接入侧粘贴激活成功；
3. 造一条已过 `activationEnd` 的密钥（签发时把窗口设到过去）→ 接入侧应报「激活窗口已关闭」；
4. 造一条 `expiry` 已过的密钥 → 报「授权已到期」；
5. 把密钥串改一个字符 → 报「密钥无效」；
6. 三步都通过后，才算接入完成。

---

## 9. 接入 Checklist

**A. 签发侧（一次性，由持有私钥的人执行）**

- [ ] 1. 打开「AVP KEYS」App，先**备份当前私钥**（点私钥旁的「复制」另存，或把备份 txt 落盘）。
      ⚠️ 该工具只保存**一把**私钥，点「生成新密钥」会覆盖它；不备份就丢失对存量密钥的签发能力。
- [ ] 2. 点「生成新密钥」→ 生成**新应用专属**的密钥对。
- [ ] 3. 复制「公钥 (hex)」交给接入侧开发；私钥按原有策略保管（加密落盘 + 离机备份），永不交付。
- [ ] 4. 确认旧应用的公钥未受影响（旧应用内嵌的是旧公钥，存量密钥验证不受影响；仅「新签发」需用旧私钥，必要时从备份恢复）。

**B. 接入侧**

- [ ] 1. 新建 `activation_public.dart`（或等价常量文件），内嵌公钥清单。
- [ ] 2. 实现 §2.2 归一化 + §3.1 校验，错误分类到 §3.3 的枚举。
- [ ] 3. 接入安全存储，落地 §4.2 的两个字段。
- [ ] 4. 实现 §4.4 的单调水位与回拨检测。
- [ ] 5. 接 UI：激活入口、输入校验反馈、剩余时间、到期锁定。
- [ ] 6. 补齐 §8.1–8.3 的测试。
- [ ] 7. 走完 §8.4 联调验收。
- [ ] 8. 确认发布包内 grep 不到任何 PKCS8 / 私钥相关代码，仅保留验签路径。

---

## 10. 参考实现（Dart / Flutter）

可直接拷进接入侧使用（去掉对签发侧的依赖，只保留验签所需部分）。

```dart
// lib/features/activation/license_key.dart
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cg;

import 'activation_public.dart';

const int kClaimsLen = 21;
const int kSigLen = 64;
const int kTokenLen = kClaimsLen + kSigLen; // 85
const int kClaimsVersion = 0x01;

/// 时钟容差（秒）：见规范 §3.2。
const int kClockSkewToleranceSec = 300;

final cg.Ed25519 _ed = cg.Ed25519();

enum LicenseError { format, version, signature, notStarted, windowClosed, expired }

/// 一次校验的完整结果：成功时 claims 非空，失败时 error 非空。
typedef LicenseCheck = ({LicenseClaims? claims, LicenseError? error});

class LicenseClaims {
  final int activationStart;
  final int activationEnd;
  final int expiry;
  final Uint8List nonce;

  const LicenseClaims({
    required this.activationStart,
    required this.activationEnd,
    required this.expiry,
    required this.nonce,
  });

  factory LicenseClaims.fromBytes(Uint8List b) => LicenseClaims(
    activationStart: _readUint32(b, 1),
    activationEnd: _readUint32(b, 5),
    expiry: _readUint32(b, 9),
    nonce: Uint8List.sublistView(b, 13, kClaimsLen),
  );
}

/// §2.2 归一化：去掉空白与分隔符，取第一段 170 位 hex，转大写。
String? normalizeToken(String raw) {
  final compact = raw.replaceAll(RegExp(r'[\s\-–—]+'), '');
  final m = RegExp(r'[0-9A-Fa-f]{170}').firstMatch(compact);
  return m?.group(0)?.toUpperCase();
}

/// §3.1 校验。`alreadyActivated=true` 时走「已激活授权复检」分支。
Future<LicenseCheck> checkLicense(
  String rawInput, {
  required int nowSec,
  required bool alreadyActivated,
}) async {
  final hex = normalizeToken(rawInput);
  if (hex == null) {
    return (claims: null, error: LicenseError.format);
  }
  final raw = _hexToBytes(hex);

  if (raw[0] != kClaimsVersion) {
    return (claims: null, error: LicenseError.version);
  }
  // 签名先行：任何时间判定都必须建立在签名有效的前提上。
  if (!await _verify(raw.sublist(0, kClaimsLen), raw.sublist(kClaimsLen))) {
    return (claims: null, error: LicenseError.signature);
  }
  final c = LicenseClaims.fromBytes(raw);

  if (alreadyActivated) {
    return nowSec > c.expiry + kClockSkewToleranceSec
        ? (claims: c, error: LicenseError.expired)
        : (claims: c, error: null);
  }
  if (nowSec < c.activationStart - kClockSkewToleranceSec) {
    return (claims: c, error: LicenseError.notStarted);
  }
  if (nowSec > c.activationEnd + kClockSkewToleranceSec) {
    return (claims: c, error: LicenseError.windowClosed);
  }
  if (nowSec > c.expiry + kClockSkewToleranceSec) {
    return (claims: c, error: LicenseError.expired);
  }
  return (claims: c, error: null);
}

/// 逐把尝试内嵌公钥（§5）。
Future<bool> _verify(List<int> message, List<int> signature) async {
  for (final hex in kActivationPublicHex) {
    final pub = _hexToBytes(hex);
    if (pub.length != 32) continue;
    final pk = cg.SimplePublicKey(pub, type: cg.KeyPairType.ed25519);
    final ok = await _ed.verify(
      message,
      signature: cg.Signature(Uint8List.fromList(signature), publicKey: pk),
    );
    if (ok) return true;
  }
  return false;
}

int _readUint32(Uint8List b, int at) =>
    ((b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]) &
    0xffffffff;

Uint8List _hexToBytes(String hex) {
  final n = hex.length ~/ 2;
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
```

### 其他平台要点

- **Kotlin/Android**：`Ed25519` via BouncyCastle 时注意 `Signature` 实例需传入原始 32B 公钥（`Ed25519PublicKeyParameters`），签名对象是 21 字节 claims；`ByteBuffer.wrap(b).order(ByteOrder.BIG_ENDIAN).getInt()` 读大端 uint32 后需 `and 0xFFFFFFFFL` 转无符号。
- **Swift/iOS**：CryptoKit `Curve25519.Signing.PublicKey(rawRepresentation:)` + `isValidSignature(_:for:)`。注意 `Data` 切片要用 `withUnsafeBytes` 取值，避免 `Data` 的 offset 陷阱。
- **JS/Web**：`crypto.subtle.importKey('raw', publicKeyBytes, {name: 'Ed25519'}, false, ['verify'])`，注意 Safari/旧版 Chromium 的支持情况；不支持时降级到 libsodium.js（`crypto_sign_verify_detached`）。

---

## 11. 待确认的决策点

以下几项不影响格式与协议，但影响接入侧实现，需要产品/业务先定：

1. **到期后的行为边界**：锁定哪些功能？已有的录制内容是否仍可导出？建议「停止受限功能 + 保留数据可导出」。
2. **是否需要设备绑定 / 激活次数限制**：v1 的格式不支持，需扩展 claims（新 version）或引入服务端。若要做，建议尽早提出，避免二次改动已交付的公众版本。
3. **时钟容差取 300 秒是否可接受**（§3.2）。
4. **是否要「续期」能力**：老用户到期后用新密钥平滑续期（token 替换不影响本地数据）。格式上天然支持，接入侧只需允许在已激活态重新输入密钥。
5. **`last_seen` 的 HMAC 保护是否需要做**（§4.4 第 4 条），取决于目标攻击者等级。
6. **多公钥清单是否现在就留好**（§5）：强烈建议现在就按清单实现，将来换密钥零成本。

---

## 附录 A · 常量速查

| 名称 | 值 |
| --- | --- |
| 密钥串长度 | 170 大写 hex 字符 / 85 字节 |
| claims 长度 | 21 字节 |
| 签名长度 | 64 字节 |
| 版本号 | `0x01` |
| nonce 长度 | 8 字节 |
| 时间单位 | UTC 纪元秒（uint32 大端） |
| 时间上限 | `0xFFFFFFFF` = 2106-02-07 |
| PKCS8 固定头（私钥，签发侧专用） | `302e020100300506032b657004220420` |
| Ed25519 OID | `1.3.101.112`（DER `2b6570`） |
| 时钟容差 | 300 秒（接入侧可配） |
| 建议的默认激活窗口 | 20 分钟（签发侧快捷档行为） |

## 附录 B · 与签发侧的格式对照

| 产出 | 格式 |
| --- | --- |
| 公钥 | 小写 hex，64 字符 |
| 私钥 | PKCS8 DER base64（48 字节 DER：16 字节固定头 + 32 字节 seed） |
| 密钥串 | 大写 hex，170 字符，无分隔符 |
| UI 展示形态 | 每 4 位插 `-`（末组 2 位），提交前须还原 |
| 「复制密钥」剪贴板内容 | `激活密钥：<170 位大写 hex>`（带前缀，须归一化） |
| Markdown 台账 | 表格，每行含「激活窗口 / 授权截止 / 密钥」三列，可整行复制 |
| 备份 txt | `私钥 (PKCS8 base64):` 与 `公钥 (hex, …):` 两段；仅签发侧使用 |

## 变更记录

| 版本 | 日期 | 变更 |
| --- | --- | --- |
| v1.0 | 2026-09-14 | 首版：Ed25519 claims 布局、校验算法、本地持久化、时钟防护、UI 与验收规范 |
