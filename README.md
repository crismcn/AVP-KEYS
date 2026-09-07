# SKEY 密钥生成器（Android 本地工具）

离线签发 SKEY 激活密钥的安卓 App。签名规则、输出格式与网页版
`../tools/keygen.html` **字节级一致**，两边的密钥对 / 备份可互换续用。

## 特性

- 深色界面，配色取自网页版工具；顶部使用仓库根目录的 `logo.png`。
- Ed25519 纯 Dart 实现，无需网络即可签发；私钥不离开本机。
- 私钥以 Android Keystore 加密落盘（`flutter_secure_storage`），启动自动恢复。
- 从 seed 直接推导公钥：只粘贴私钥也能补出配套公钥（网页版做不到）。
- 可从磁盘选择备份 `.txt` / base64 文件导入密钥（内容与网页版备份文件同格式）。
- 密钥串与网页版同为 170 大写 hex，可复制为 Markdown 台账。

## 本地开发

```sh
flutter pub get
flutter test                 # RFC 8032 向量 + 格式 + PKCS8 往返 + 端到端
flutter run                  # 连接安卓设备/模拟器
flutter build apk --release  # 产物在 build/app/outputs/flutter-apk/app-release.apk
```

重新生成启动图标 / App 图标（改过 logo.png 后执行）：

```sh
python3 tools/gen_icons.py
```

它从根目录 `logo.png` 一次性写出自适应图标（`ic_launcher_foreground` /
`ic_launcher_monochrome`，供 `mipmap-anydpi-v26` 用）与旧版 `ic_launcher`，
启动画面（`drawable*/launch_background.xml`）居中 logo 复用的正是前景图层，
所以重跑后启动图标也会自动更新。产物还含 `design/logo-mark.png` 与
`design/play-store-icon-512.png`。

## 使用

1. 「1 · 密钥对」点**生成新密钥** → 把下方**公钥**粘贴进 App 源码
   `lib/features/activation/activation_public.dart` 并重新打包 App；
   私钥自动加密保存，可用私钥旁的**复制**留档。已有备份文件则点**导入密钥**从磁盘选入。
2. 「2 · 激活参数」授权时长可点「30 分钟 / 1 小时 …」快捷档一键设置；
   三个具体时间也可点行微调。生成数量用步进器。
3. 「3 · 生成清单」点**生成密钥**，逐条复制或「复制台账」。

## 与网页版互通

- 网页版导出的备份 `.txt` 可用本 App「导入密钥」从磁盘选入续用；
- 本 App 私钥框的「复制」可把 PKCS8 base64 粘回网页版「私钥」框（公钥须一致）。
- 无论哪边签发，密钥串格式与验签规则均相同。
