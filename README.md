# 物灵 · Wuling

> 拍下一件旧物，唤醒它的物灵。道一声谢，然后放手；或者，把它和它的故事一起传给下一个人。

黑客松项目 · Track 1 · Apple Human-Centered Care
技术栈：Swift · SwiftUI · Liquid Glass · Metal（GPU 墨点粒子 · 水面着色器） · Core ML（FastViT · Depth Anything） · Vision · Foundation Models · SceneKit · Object Capture · AR Quick Look · MultipeerConnectivity · TipKit · AMD 图像生成 API

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
| 音效与背景音乐 | ✅ 跟随静音开关；别的 App 在放音乐时不放背景音乐 | ✅ |
| 长按送别的渐强触感（Core Haptics） | ✅ | ❌ 模拟器没有触感 |

没有 Apple 智能的机型（国行、旧机型）用模板起名时，也会读用户写下的记忆：认出「深夜、清晨、下雨、考研、外婆送的、搬家……」这类画面，回一句贴合的性格描述和送别语；没认出时，轻轻呼应记忆里的一个短语，不照抄整句。

**路演请用真机演示。**

### 演示：换景
首页右上角的 **⛰ 换景** 按钮，或者轻点山水右侧的**节气题签**，可以把园林换到任何时辰、季节和天气：
- **意境**：八幅诗意的景，例如「斜风细雨」「夏夜流萤」「秋江月夜」「寒江独钓」，一点就换，新景会像墨一样从题签处晕开
- **细调**：时辰（晨 / 昼 / 暮 / 夜）、四季、天气（晴 / 雨 / 雪 / 岚）可以单独指定，其余仍跟随真实时间
- 选「夜」时整个 App 会进入深色；选「此时此刻」恢复跟随真实的时辰与节气
- **演示河灯与鸿雁**：图鉴还是空的时候，也能在水上点几盏河灯、远天放一行鸿雁
- 轻点山水：水面荡开涟漪，山和天上晕开一点淡墨

### 演示：送别的墨与水
长按印章送别时，抠出来的旧物会被拆成几千个墨点（Metal 渲染管线，轨迹在顶点着色器里按时间算出），顺着风飘落到水面上，再沿着弧线汇聚成一盏亮起的河灯。
- 水面是一个 SwiftUI 的 Metal 着色器：波纹来自真实的二维波动方程（会扩散、在岸边反射、相互叠加、慢慢平息），水线以上的物件、物灵插画和河灯都会倒映在水里
- 河灯落水时荡开一圈涟漪，漂走时身后拖出细细的水纹；送别前轻点水面，也能荡开涟漪
- 设备不支持 Metal 时，自动退回原来的光点动画

### 演示：声音与手感
- **背景音乐**：古琴般的拨弦、泛音、远处的水声，五声音阶，全部用代码合成（`tools/compose_ambient.py`，无版权素材）。白天、夜里各一段；换到「雨」时添一层雨声；换景时交叉淡入淡出。醒来、送别、来信时音乐会先退到远处，留出风铃和水声
- **点水面会响**：首页园林的水面从左到右排着一组五声音阶（和背景音乐同一组音），连着点就像在弹水；点山和天是毛笔"嗒"地一点
- **长按送别**：触感从几乎感觉不到慢慢涨上来，叠着越来越快的心跳；一段和音跟着涨，印章越来越"沉"、快满时微微发颤；走满的一刻重重一"咚"，一圈朱色波纹荡开，风声把它吹散成墨点。中途松手，声音像一口气轻轻呼出
- 其余的小声音：快门、贴纸揭起、立牌蹦一下、拨动选项、信笺展开的纸声
- 换景面板里可以分别关掉「背景音乐」和「音效」；手机静音时都不出声
- **路演**：记得打开铃声开关、调大音量

### 演示：节气来信
送别（或传出）过的物灵，每逢新节气会托河灯（传出的托鸿雁）捎回一张短笺；送别周年那几天，则由那位物灵来信。首页标题下会亮起「一封来信」，点开是一张竖排的八行笺：一句当季物候、一句贴着记忆的问候、「一切都好，勿念」，落款是物灵的名章和干支日期。
- **不用等节气**：换景面板最下面的「演示 → 收一封节气来信」，面板收起后马上来信。图鉴里还没有送别过的物灵时，用示例物灵「青履君」
- 不改数据表：信的内容由送别日期、名字、记忆和今天的节气算出来，读过哪几封只记在本机

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

### 接入 AMD 图像生成 API（比赛必须）
比赛要求**必须调用 AMD 图像生成 API，并提交项目海报**。现在接的是 **AiHubMix 平台的 `gpt-image-2.6-flare`**，按 OpenAI 兼容的 `/v1/images/generations` 格式调用。
没有配置时 App 会用离线水彩剪影代替，流程照样能完整演示。

1. 复制 `Wuling/Resources/Secrets.example.plist`，改名为 `Secrets.plist`，放在同一个文件夹
2. 把里面的 `IMAGE_API_KEY` 换成真实的 Key（地址 `https://api.inferera.com`（AiHubMix 中国大陆直连域名，免代理）、模型 `gpt-image-2.6-flare` 已经填好），重新运行 App
3. **海报**已经生成好：中文版 `posters/poster.png`、英文版 `posters/poster-en.png`（插画原图 `posters/poster-art.png`，用 `gpt-image-2` high 画质画的）。要重新生成（在仓库根目录运行）：
   ```bash
   python3 -m pip install pillow
   python3 tools/generate_poster.py
   ```
   会调用 API 画一张 1024×1536 的 high 画质插画，再排版成竖版海报；只改文字时加 `--art posters/poster-art.png`，不花钱

`Secrets.plist` 已加入 `.gitignore`，**不会被提交**，每台 Mac 都要自己建一份。

实测（1024×1024，同样的物灵提示词）：

| 模型 · 画质 | 用时 | 每张花费 | 说明 |
| --- | --- | --- | --- |
| **`gpt-image-2.6-flare` · `low`（默认）** | 约 5 秒 | 约 0.026 美元 | 唤醒动画还没放完图就到了，路演用它 |
| `gpt-image-2` · `low` | 约 14–15 秒 | 约 0.007 美元 | 更便宜，但现场要多等十秒 |
| `gpt-image-2` · `medium` | 约 37 秒 | 约 0.055 美元 | 笔触更丰富，但现场等不起 |

App 等 120 秒还没出图，就换成离线水彩剪影，不会卡住。

### 上台前检查
- [ ] 两部演示手机都是 **iOS 26 或更高**（设置 → 通用 → 关于本机）
- [ ] Mac 上装好 **Xcode 26 或更高**，并且运行过一次 `sudo xcode-select -s /Applications/Xcode.app`
- [ ] 演示用的 Mac 上建好 `Secrets.plist`，真机上唤醒过一次，确认能出图（约 15 秒）
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
├── Services/               抠图、识别、取色、起名与记忆回应、提示词、图像 API、相机、节气、面对面连接、音效与背景音乐、长按触感
└── Resources/              App 图标、FastViT 识别模型、Depth Anything 深度模型、API 配置模板
Wuling-Info.plist           声明 .wuling 文件类型（传灵用）
tools/make_icon.py          生成 App 图标的脚本
tools/generate_poster.py    调用 AMD API 生成项目海报
tools/compose_ambient.py    合成背景音乐（Resources/Sounds）
promo/index.html            五页宣传页（单文件，素材都内嵌，双击即可离线打开）
tools/mac_watch.sh          Mac 上自动编译、截图并回报给 Claude
```

## 隐私
- 抠图、物品识别、起名**全部在手机上完成**
- **照片不上传**。生成插画时只发送"物品类别、颜色、陪伴时长"这几项文字
- 用户写下的记忆只保存在本机
