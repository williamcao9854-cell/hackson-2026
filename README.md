# 物灵 · Wuling

> 拍下一件旧物，唤醒它的物灵。道一声谢，然后放手；或者，把它和它的故事一起传给下一个人。

黑客松项目 · Track 1 · Apple Human-Centered Care
技术栈：Swift · SwiftUI · Liquid Glass · Core ML（FastViT · Depth Anything） · Vision · Foundation Models · SceneKit · Object Capture · AR Quick Look · MultipeerConnectivity · TipKit · AMD 图像生成 API

- 📐 [开发计划](docs/PLAN.md)：设计调研、设计语言「和纸与朱印」、技术方案
- 💡 [创意方案 v4](docs/IDEAS-v4.md)：物灵是从这里选出来的
- 🗂️ 历史方案：[v3](docs/IDEAS-v3.md) · [v2](docs/IDEAS-v2.md) · [v1](docs/PRODUCT.md)

---

## 在 Mac 上运行

**需要**：Xcode 26 或更高版本；真机需要 iOS 26 或更高版本

1. 拉取代码
   ```bash
   git clone git@github.com:williamcao9854-cell/hackson-2026.git
   cd hackson-2026
   ```
2. 双击打开 `Wuling.xcodeproj`
3. 左侧选中项目 **Wuling** → **Signing & Capabilities** → **Team** 选你自己的 Apple ID
   （如果提示 Bundle Identifier 已被占用，把 `com.hackson2026.wuling` 改成别的，比如加上你的名字）
4. 顶部选择你的 iPhone 或模拟器，按 **⌘R** 运行

### 🤖 自动编译，和 Claude 联动（推荐）
Mac 上运行一个脚本，它会盯着 GitHub：Claude 每推一次修复，Mac 就自动拉取、编译，并把**报错或模拟器截图**推回 GitHub 的 `ci-feedback` 分支，Claude 看到后继续修。你不需要手动转发报错。

```bash
cd ~/Desktop/hackson-2026
bash tools/mac_watch.sh
```
让这个终端窗口一直开着就行，按 Ctrl+C 停止。前提是这台 Mac 能 push 到 GitHub（见下面）。

**让 Mac 能 push 到 GitHub（只需一次）：**
```bash
brew install gh          # 没有 Homebrew 的话，先去 https://brew.sh 安装
gh auth login            # 选 GitHub.com → HTTPS → 用浏览器登录
gh auth setup-git
```

### 真机还是模拟器？
| | 真机 | 模拟器 |
|---|---|---|
| 拍照 | ✅ | ❌ 没有相机，可以从相册选图 |
| 主体抠图（Vision） | ✅ | ⚠️ 可能不支持，会自动退回"照片贴纸" |
| Core ML 识别 | ✅ | ✅ |
| 设备端起名（Foundation Models） | ✅ 支持 Apple 智能的机型 | ⚠️ 取决于 Mac，不可用时自动用模板起名 |

**路演请用真机演示。**

### 演示：换景
首页右上角的 **⛰ 换景** 按钮，或者轻点山水右侧的**节气题签**，可以把园林换到任何时辰、季节和天气：
- **意境**：八幅诗意的景，例如「斜风细雨」「夏夜流萤」「秋江月夜」「寒江独钓」，一点就换，新景会像墨一样从题签处晕开
- **细调**：时辰（晨 / 昼 / 暮 / 夜）、四季、天气（晴 / 雨 / 雪 / 岚）可以单独指定，其余仍跟随真实时间
- 选「夜」时整个 App 会进入深色；选「此时此刻」恢复跟随真实的时辰与节气
- **演示河灯与鸿雁**：图鉴还是空的时候，也能在水上点几盏河灯、远天放一行鸿雁
- 轻点山水：水面荡开涟漪，山和天上晕开一点淡墨

截图或录屏时也可以用启动参数直接指定：Xcode → Product → Scheme → Edit Scheme → Arguments，加上 `-scene night.autumn.clear`（顺序是 时辰.季节.天气，不想指定的写 `auto`）。

> **AR 摆在桌上**只在带 LiDAR 的机型（iPhone 12 Pro 及之后的 Pro 机型）上出现；其他机型的「手办」只能在屏幕里拖动转着看。

### 测试「传灵」（面对面）
需要两部装了物灵的 iPhone，打开蓝牙和无线局域网（不需要连同一个网络）：
1. **手机 B**：首页点 **接灵**，写下名章，等待
2. **手机 A**：点开一个"同住"的物灵 → **传给下一位** → 写名章和留言 → **盖上名章** → **面对面传给 TA**
3. 手机 A 上会出现 B 的名章，点一下；B 点 **收下**，物灵化作鸿雁飞过去
4. B 盖上自己的名章，物灵住进 B 的园林

第一次使用时，两台手机都会弹出"允许访问本地网络"，请点**允许**。
如果面对面连不上，也可以选"其他方式发送"，通过隔空投送或微信传 `.wuling` 文件。

### ⚠️ 接入 AMD 图像生成 API（比赛必须）
比赛要求**必须调用 AMD 图像生成 API，并提交项目海报**。运行 App 本身不依赖它，没有配置时会用离线水彩剪影代替，但**路演和提交前一定要接上**。

1. 复制 `Wuling/Resources/Secrets.example.plist`，改名为 `Secrets.plist`，放在同一个文件夹
2. 填入 API 地址、Key、模型名，重新运行 App
3. **生成海报**（在仓库根目录运行）：
   ```bash
   python3 -m pip install pillow
   python3 tools/generate_poster.py
   ```
   会调用 AMD API 画插画，再排版成竖版海报，保存在 `posters/poster.png`

`Secrets.plist` 已加入 `.gitignore`，**不会被提交**。
接口默认按 OpenAI 兼容的 `/v1/images/generations` 格式调用，格式不同的话只需要改 `Wuling/Services/ImageGeneration.swift` 和 `tools/generate_poster.py`。

### 上台前检查
- [ ] 两部演示手机都是 **iOS 26 或更高**（设置 → 通用 → 关于本机）
- [ ] Mac 上装好 **Xcode 26 或更高**，并且运行过一次 `sudo xcode-select -s /Applications/Xcode.app`
- [ ] 接好 AMD API，真机上试过几次，记下每次生成大概要多久
- [ ] 海报已生成
- [ ] 深色模式、浅色模式都检查过一遍

### 项目打不开？
- **备用方案 1**：`brew install xcodegen && xcodegen generate`，会根据 `project.yml` 重新生成项目
- **备用方案 2**：Xcode 新建一个 iOS App 项目（SwiftUI，最低 iOS 26），删掉自动生成的 Swift 文件，把 `Wuling/` 文件夹整个拖进去，在 Info 里加上相机权限说明 `NSCameraUsageDescription`

### 编译报错？
这份代码是在没有 Xcode 的环境里写的（已通过 Swift 6.4 语法检查，核心逻辑通过了单元测试），第一次编译可能会有少量报错。**把报错原文复制给 Claude**，很快就能修好。

---

## 代码结构

```
Wuling/
├── App/                    入口、预览数据
├── Design/                 设计系统：颜色、字体、和纸背景
│   ├── Components/         竖排文字、朱印、贴纸、亚克力立牌、长按送别、河灯、鸿雁、TipKit 提示
│   └── Landscape/          会呼吸的水墨山水（时辰、节气、河灯、鸿雁），以及各页面的淡山水背景
├── Features/
│   ├── Collection/         园林首页、图鉴、物灵详情（立牌/画作/原貌）、分享卡片、关于
│   ├── Onboarding/         第一次打开的三页引导
│   ├── Encounter/          遇见流程：取景 → 讲讲它 → 唤醒 → 初见 → 送别
│   ├── Relay/              传灵：盖章传出、面对面传 / 接灵、收下物灵
│   └── Scan/               LiDAR 精细扫描（Object Capture）
├── Models/                 物灵（SwiftData）、陪伴时长、传灵章节与胶囊
├── Services/               抠图、识别、取色、起名、提示词、图像 API、相机、节气、面对面连接
└── Resources/              App 图标、FastViT 识别模型、Depth Anything 深度模型、API 配置模板
Wuling-Info.plist           声明 .wuling 文件类型（传灵用）
tools/make_icon.py          生成 App 图标的脚本
tools/generate_poster.py    调用 AMD API 生成项目海报
tools/mac_watch.sh          Mac 上自动编译、截图并回报给 Claude
```

## 隐私
- 抠图、物品识别、起名**全部在手机上完成**
- **照片不上传**。生成插画时只发送"物品类别、颜色、陪伴时长"这几项文字
- 用户写下的记忆只保存在本机
