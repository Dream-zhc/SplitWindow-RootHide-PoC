# SplitWindow-RootHide 项目交接文档

> 面向一个**完全没有上下文的新会话**。请先完整读完本文，再动代码。
>
> 当前目标设备环境：**iOS 16.0 + Dopamine RootHide（隐根）**。
> 当前仓库：`Dream-zhc/SplitWindow-RootHide-PoC`
> 当前分支：`main`
> 当前代码基线：**v0.4.0 emergency isolation series**；以 `git log` 最新 HEAD 为准。
> `6f5c8fb` 仅保留为历史参考，**禁止回退为单 dylib 自动注入完整 UI/FrontBoard 功能代码的结构**。

## 0. 2026-08-07 紧急修复：安装即 SpringBoard 死机

用户反复确认：此前包安装/Respring 后会导致 SpringBoard 黑屏/死机，必须卸载 tweak 才恢复。

因此 v0.4.0 不再依赖“完整 dylib 已加载，但 ctor 不主动 start”这种软隔离，而改成**物理模块隔离**：

1. `SplitWindow.dylib` 是自动注入 SpringBoard 的最小 Loader。
   - 已改为纯 C (`Tweak/Loader.c`)。
   - 自动加载阶段只依赖 CoreFoundation + libSystem。
   - 不包含 Foundation/libobjc/UIKit/QuartzCore/FrontBoard/Overlay/SceneHost 代码。
   - ctor 只注册 Darwin notification，不读设置、不写日志、不建 UIWindow、不碰 FBScene、不 dlopen Feature。
2. `SplitWindowFeature.dylib` 才包含 UIKit / `SWOverlayController` / `SWSceneHost`。
   - 安装到 `/Library/SplitWindow`，不位于 tweak 自动扫描目录。
   - 只有用户在设置里**显式开启**后，Loader 才会 `dlopen` Feature。
   - SpringBoard 如果因 Feature 崩溃并重启，Loader 不会因为已有 Enabled 值而自动重新加载 Feature，因此不会形成无限黑屏循环。
3. 启用键从旧 `Enabled` 改为 `EnabledV040`。
   - 卸载 tweak 不一定清除旧 preferences。
   - 旧版本遗留的 `Enabled=true` 必须被 v0.4.0 完全忽略，避免安装后意外自动激活。
4. UIWindow 创建改为 fail-closed。
   - 只接受 foreground active/inactive 的 `UIWindowScene`。
   - 不再随便取 fallback scene。
   - 不再 fallback 到 `initWithFrame:`。
   - host window 不再调用 `makeKeyAndVisible` 抢 SpringBoard key window。
5. CI 增加强制门禁。
   - Loader 必须 `arm64 + arm64e`。
   - Loader 动态依赖中出现 Foundation/libobjc/UIKit/QuartzCore/FrontBoard 直接失败。
   - Loader 字符串中出现 `SWOverlayController` / `FBSceneManager` / Scene host selectors 直接失败。
   - Feature dylib 必须单独存在并包含 `arm64 + arm64e`。

本地已用现有 Theos + patched iPhoneOS16.5 SDK 做 rootless **源码/链接 sanity build**，Feature、Loader、Prefs 均成功完成 arm64/arm64e 编译和打包；该本地 rootless deb 只用于编译验证，**不得作为最终 RootHide 实机测试包交付**。最终仍必须由 `roothide/theos` + `THEOS_PACKAGE_SCHEME=roothide` 构建并通过 CI 门禁后再给用户安装。

---

## 1. 我们在做什么

我们在做一个 **iOS 16 / Dopamine RootHide 的系统级小窗/分屏 PoC tweak**。

不是截图、录屏、镜像或假窗口；目标是把另一个 App 的**真实 App Scene**托管到 SpringBoard 上方的小窗中，让它可以真正点击、滑动、输入。

### 第一版已经确认的产品需求

1. **真实可交互小窗**
   - App 必须是真实 Scene，不允许用截图/镜像冒充。
   - 小窗内可点击、滑动、滚动，后续要验证键盘输入。

2. **同时只允许一个小窗 App**
   - 新打开 B App 时，直接替换/关闭 A App 小窗。

3. **底层当前 App 保持可见且继续实时运行**
   - 例如底层视频/动画继续更新。
   - 第一版不要求底层 App 同时接收触摸；触摸优先给小窗。

4. **两个入口都要有**
   - 屏幕边缘向内滑动打开 App 面板。
   - 悬浮按钮作为调试/备用入口。

5. **第一版只做竖屏**
   - 暂不处理横屏游戏、全屏视频旋转、横竖屏重布局。

6. **第一版固定比例小窗**
   - 约屏幕宽度 70%~75%。
   - 可以拖动、关闭。
   - 第一版不做自由缩放。

7. **系统设置页管理 App 白名单**
   - `设置 -> SplitWindow`
   - 从已安装 App 中勾选哪些 App 出现在侧边面板。

8. **目标是 RootHide 原生构建**
   - 当前代码已回到 `THEOS_PACKAGE_SCHEME=roothide`。
   - 不要把 rootful 包拿去碰运气。

---

## 2. 技术路线：不要重新造轮子

前期已经调研过这类实现。核心路线是 **FrontBoard Scene Hosting**。

重点参考：

- **Konban**
  - 经典开源实现。
  - 核心思路：拿 `FBScene`，再用 Scene Host / layer host 把真实 App Scene 显示到 SpringBoard。

- **Zetsu**
  - 后续更成熟的窗口多任务 tweak。
  - 有 iOS 16 使用/测试参考。

- **FrontBoardAppLauncher**
  - 更现代的 iOS 15+ FrontBoard/UIKit 私有 API Scene 展示参考。
  - 适合作为 modern presenter 路线参考。

- **LiveContainer 的多任务/键盘研究**
  - 对 keyboard focus、visibility、RunningBoard 等有进一步参考价值。

### 当前设计思路

`SWSceneHost` 负责：

1. 获取/创建目标 App 的 `FBScene`。
2. 尝试将 Scene 置前台状态。
3. 优先尝试现代 presentation API。
4. 必要时 fallback 到 Konban 风格的 legacy layer-host。
5. 把返回的真实 view 放入 SpringBoard 自己的小窗容器。

**绝对不要退化成截图/屏幕镜像方案来“看起来像成功”。**

---

## 3. 当前仓库结构

核心目录：

```text
SplitWindow-RootHide-PoC/
├── .github/workflows/build.yml
├── Makefile
├── control
├── Tweak/
│   ├── Makefile
│   ├── Tweak.xm
│   ├── SplitWindow.plist
│   ├── SWLogger.h/m
│   ├── SWPreferences.h/m
│   ├── SWSceneHost.h/m
│   └── SWOverlayController.h/m
├── Prefs/
│   ├── Makefile
│   ├── SWRootListController.m
│   ├── SWAppListController.m
│   ├── Info.plist
│   └── Resources/Root.plist
├── layout/
│   └── Library/PreferenceLoader/Preferences/SplitWindow.plist
└── HANDOFF.md
```

---

## 4. 已经完成了什么

### 4.1 基础 tweak + 设置页骨架已完成

- SpringBoard 注入 filter 已存在。
- App 白名单 preferences 已存在。
- 悬浮按钮、边缘手势、小窗容器等基础代码已存在。
- Scene Host 逻辑已有 PoC。
- PreferenceLoader 设置页已经接入。

### 4.2 已加入“安全启动模式”

这是当前最重要的安全改动。

初版曾经在安装后导致：

> **SpringBoard 一直黑屏 / 无法进桌面，强制重启后必须卸载 tweak 才恢复。**

因此当前 `Tweak/Tweak.xm` 已改成：

- `%ctor` 只做极少工作。
- **SpringBoard 启动时绝不自动创建 UIWindow。**
- **SpringBoard 启动时绝不自动做 FrontBoard Scene Hosting。**
- 只注册 preferences Darwin notification。
- 只有用户在 Settings 里显式触发 enable/preferences change 后，才允许 `SWOverlayController start`。

也就是说：

```text
安装 / Respring
  -> dylib 被注入
  -> 保持 PASSIVE
  -> 不自动创建 overlay
  -> 不自动碰 FBScene
```

这条原则**绝对不要破坏**。

### 4.3 UIWindowScene 选择逻辑已经按已验证项目修正

之前有一个非常危险的错误：

> 直接拿 `UIApplication.sharedApplication.connectedScenes` 的第一个 Scene。

在 SpringBoard 里这不安全。

已经参考用户现有、可在 RootHide 实机运行的 `ioscpy-dream` 项目，改成优先选择：

- `UISceneActivationStateForegroundActive`
- `UISceneActivationStateForegroundInactive`

再考虑 fallback。

新会话如果要继续调整 UIWindow，优先参考 `ioscpy-dream` 里 `device/tweak/PairingOverlay.mm` 的 window scene 选择方式。

### 4.4 已加入文件日志

用户明确要求后续能直接把日志文件给我们。

当前日志路径：

```text
/var/mobile/SplitWindow/logs/splitwindow.log
```

轮转文件：

```text
/var/mobile/SplitWindow/logs/splitwindow.log.1
```

约 512 KB 自动轮转。

为什么没有写 `/logs`：

- RootHide 的 jailbreak 根是动态 prefix。
- `/` 也不是一个适合随便创建调试目录的稳定写入点。
- `/var/mobile/SplitWindow/logs` 对测试最简单、最稳定。

日志里要持续保留/增加**阶段标记**，不要只写模糊的“failed”。例如：

```text
BOOT-OK
PREF
UI-1
UI-2
SCENE-1
SCENE-2
SCENE-3
HOST-4
HOST-5
```

下一轮 runtime 调试应依赖这些日志确定崩在哪一步。

### 4.5 RootHide 构建已经重新纠正

当前最新提交：

```text
6f5c8fb fix: build native RootHide arm64 arm64e package
```

当前版本号：

```text
0.3.1
```

关键修正：

- 根 `Makefile`：

```make
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:16.0
export THEOS_PACKAGE_SCHEME = roothide
export DEB_ARCH = iphoneos-arm64
```

- `Tweak/Makefile` 和 `Prefs/Makefile` 也显式指定：

```make
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
```

- CI 使用：

```text
roothide/theos
```

- CI 安装 patched：

```text
iPhoneOS16.5.sdk
```

- deployment target 仍是：

```text
iOS 16.0
```

- 构建命令会再次显式传：

```text
ARCHS="arm64 arm64e"
TARGET="iphone:clang:16.5:16.0"
THEOS_PACKAGE_SCHEME=roothide
DEB_ARCH=iphoneos-arm64
```

- CI 还会检查最终 dylib slices，必须包含：

```text
arm64
arm64e
```

如果出现：

```text
armv7
armv7s
```

CI 应直接失败。

### 4.6 Objective-C++ / C linkage 问题已经修复

`Tweak.xm` 会按 Objective-C++ 编译，`SWLogger.m` 是 Objective-C。

之前 linker 明确报过：

```text
SWLogMessage ... declaration possibly missing extern "C"
SWLoggerInitialize ... declaration possibly missing extern "C"
```

当前 `SWLogger.h` 和相关 exported constants 已加：

```cpp
#ifdef __cplusplus
extern "C" {
#endif

...

#ifdef __cplusplus
}
#endif
```

这类 linkage 修复不要撤掉。

---

## 5. 当前卡在哪里

当前**代码本身已经提交到 `main`，且本地与 `origin/main` 同步**。

当前最大的阻塞不是代码编辑，而是：

> **需要跑最新 `6f5c8fb` 的 GitHub Actions，确认这次 RootHide/arm64/arm64e 构建是否真正成功，然后下载 `.deb` 实机测试。**

本会话里曾多次尝试使用 GitHub MCP，但当时 ChatGPT 工具注册表里没有暴露 `GitHub` namespace；本地 `gh` 也没有登录。

所以新会话第一件事应该是：

1. 检查 GitHub MCP 是否已经真正可用。
2. 如果可用，直接操作 `Dream-zhc/SplitWindow-RootHide-PoC`。
3. 查看 `main` 最新 Actions。
4. 如果最新 commit 没有跑，触发 `Build RootHide DEB`。
5. 如果失败，直接读完整 job log，按**第一个真实错误**修。
6. 如果成功，下载 artifact，把最终 `.deb` 下载到本地并把本地路径/链接给用户。

用户已经明确表示：

> 后续版本更新完，最好直接给 `.deb`，不要再让他手工搬 ZIP、手工上传代码。

---

## 6. 最近一次失败日志及真正根因

用户最后给过一份完整 Actions 日志。

日志最前面已经说明当时 CI 配置失效：

```text
Warning: Building for iOS 9.0
Compiling Tweak.xm (armv7)
Compiling SWPreferences.m (armv7)
...
Linking tweak SplitWindow (armv7)
```

而 Xcode 26 SDK 没有 armv7 slice，于是后面出现大量 Foundation/UIKit/CoreFoundation/Objective-C undefined symbols。

这些几百条 undefined symbol **不是几百个独立 bug**，只是“错误架构 + 错误 target”的连锁反应。

同时该日志还暴露过 C++ name mangling：

```text
declaration possibly missing extern "C"
```

上述两个根因都已经在 `6f5c8fb` 修复。

### 因此下一次 Actions 必须先看前 20 行

正确的日志应该类似：

```text
Making all for tweak SplitWindow...
Compiling ... (arm64)
...
Compiling ... (arm64e)
```

**如果再次看到 armv7 或 iOS 9.0，立刻停，不要分析后面的 linker 垃圾。**

---

## 7. 我们踩过的坑：新会话绝对不要再踩

### 坑 1：安装后自动启动 overlay / Scene Host

这是最严重的一次事故。

后果：

- 手机 SpringBoard 黑屏。
- 强制重启仍无法正常进桌面。
- 用户最后通过卸载 tweak 才恢复。

**禁止：**

- 在 `%ctor` 直接创建 UIWindow。
- 在 SpringBoard 启动完成 hook 里自动创建 overlay。
- 安装后自动调用 `FBScene` / presenter。
- 让 crash 后的 SpringBoard 再次自动触发相同危险代码，形成 respring/黑屏循环。

当前 safe-start 是底线。

### 坑 2：直接取 `connectedScenes` 第一个 Scene

SpringBoard 有多个 Scene，不能假设第一个就是正确 window scene。

优先找 foreground active/inactive。

### 坑 3：把“编译成功”当成“RootHide 正确”

RootHide 最危险的地方是：

- rootful/rootless/roothide 三种 scheme 可以“看似都能出包”。
- 出包不代表能在目标环境安全注入 SpringBoard。

当前目标明确是：

```text
roothide/theos
THEOS_PACKAGE_SCHEME=roothide
iphoneos-arm64 package arch
arm64 + arm64e Mach-O slices
```

必须在 CI 里验证最终二进制，不要只看 `make package` exit 0。

### 坑 4：子 Makefile 没继承架构/target

之前根 Makefile 明明写过 `arm64 arm64e`，实际 CI 仍跑出了：

```text
armv7 + iOS 9.0
```

所以现在：

- 根 Makefile `export`
- 子项目 Makefile 再显式设置
- Actions 构建命令再显式传值

三层保险。

不要为了“代码更干净”把这些去掉，除非你已经证明 RootHide Theos 的变量传播在当前环境可靠。

### 坑 5：Private Framework `Preferences` 不是普通 Xcode SDK 自带可链接框架

之前设置 Bundle 链接报过：

```text
ld: framework 'Preferences' not found
```

`Prefs/Makefile` 使用的是：

```make
SplitWindowPrefs_PRIVATE_FRAMEWORKS = Preferences
```

这本身是对的。

问题在 SDK：CI 需要 Theos patched SDK，里面有 private framework stubs。

现在 workflow 会拉：

```text
theos/sdks -> iPhoneOS16.5.sdk
```

不要把 `PRIVATE_FRAMEWORKS` 改成普通 `FRAMEWORKS` 来绕。

### 坑 6：`Tweak.xm` 是 Objective-C++，别忘了 C linkage

如果 `.xm` 调用 `.m` 文件里的 C 函数/全局导出符号，header 要考虑：

```cpp
extern "C"
```

否则会出现“函数明明编译进去了，但链接器说找不到”的情况。

### 坑 7：不要每次只修编译器暴露的一个表面 warning

曾经有一次：

```text
unused function 'SWMsg2' [-Werror]
```

当时只是删除 unused 函数即可。

但后来的 armv7 日志不能按这个思路一条条修 undefined symbol；必须先识别**共同根因**。

### 坑 8：不要再让用户手工维护多个 ZIP

用户已经明确要求工作方式：

```text
MCP 修改仓库
-> 自己 commit/push
-> GitHub Actions
-> 下载 .deb
-> 只把最终 deb 给用户
```

除非 GitHub/MCP 真不可用，不要回到“一版一个 ZIP，让用户网页上传”的流程。

### 坑 9：不要在小窗 UI 没意义的地方过早做大重构

当前真正高风险优先级：

```text
SpringBoard 能否安全加载
>
RootHide 包是否正确
>
FBScene 是否能创建/获取
>
Scene Hosting 是否能显示
>
触摸
>
键盘 focus
>
底层 App 是否持续 live
>
UI 美化
```

不要先做 Flyme 动画、自由缩放、多窗口、复杂毛玻璃。

---

## 8. RootHide 和用户现有项目的参考价值

用户还有一个已经实际运行的项目：

```text
https://github.com/Dream-zhc/ioscpy-dream
```

这个项目对 RootHide 实机兼容非常有参考价值。

之前从其中确认过：

- 目标设备/文档中有 RootHide + ElleKit 的实际使用。
- SpringBoard tweak filter：`com.apple.springboard`。
- iOS 16 target。
- `arm64 arm64e`。
- UIWindowScene 使用 foreground active/inactive 选择逻辑。
- RootHide 不能硬编码 jailbreak 根路径。

如果 SplitWindow 出现 RootHide 注入、路径、UIWindow 生命周期问题，**优先拿 ioscpy-dream 里已经在设备上跑过的代码做参照**，不要凭空设计一套“理论上应该能工作”的 RootHide 结构。

---

## 9. 下一步计划（严格按顺序）

### Step 1：确认 GitHub 最新 commit

仓库：

```text
Dream-zhc/SplitWindow-RootHide-PoC
```

必须确认 `main` HEAD 是：

```text
6f5c8fb8bd4d973f2a96a9393e748f4931ae997b
```

版本：

```text
0.3.1
```

### Step 2：跑 GitHub Actions

工作流：

```text
Build RootHide DEB
```

先看开头必须是：

```text
arm64
arm64e
```

不能再出现：

```text
armv7
iOS 9.0
```

### Step 3：如果 Actions 失败

只处理**第一个根因**。

尤其先检查：

1. `roothide/theos` 是否拉取成功。
2. patched `iPhoneOS16.5.sdk` 是否存在。
3. `Preferences.framework/Preferences.tbd` 是否存在。
4. `TARGET` / `ARCHS` 是否真传到 Tweak 和 Prefs。
5. 最后再看具体 compiler/linker 错误。

### Step 4：Actions 成功后做 artifact 验证

必须确认：

- Package Architecture：`iphoneos-arm64`
- `SplitWindow.dylib` slices：`arm64 arm64e`
- 不包含 armv7/armv7s。
- package 内存在：
  - `SplitWindow.dylib`
  - `SplitWindow.plist`
  - `SplitWindowPrefs.bundle`

### Step 5：下载 `.deb`

下载 GitHub Actions artifact 到本地，最后直接给用户：

```text
绝对本地路径 / 可点击下载链接
```

用户后续希望每一版都这样交付。

### Step 6：第一轮实机只测“安全加载”

不要一装完立刻开 Scene Host。

顺序：

1. 安装 `.deb`。
2. Respring。
3. 确认可以正常进桌面，不黑屏。
4. 等 8 秒。
5. 取日志：

```text
/var/mobile/SplitWindow/logs/splitwindow.log
```

应该看到类似：

```text
BOOT-OK SpringBoard survived 8s after SplitWindow injection; overlay still passive
```

**如果这一步都不稳，禁止继续 Scene Hosting。**

### Step 7：再测 Settings/preferences

1. 打开 `设置 -> SplitWindow`。
2. 确认 Preference Bundle 正常加载。
3. 选择计算器/备忘录。
4. 显式 enable。
5. 再看日志。

### Step 8：再测 overlay，不要先测微信

先验证：

- 悬浮按钮。
- 边缘手势。
- panel。

再验证 Scene：

1. Calculator。
2. Notes。
3. 触摸。
4. 多次打开/关闭。
5. 最后才测微信。

### Step 9：最后处理双 Scene / 键盘

只有 Scene 本身稳定以后，再进入：

- RunningBoard assertion
- visibility / foreground state
- keyboard focus
- 两个 App 同时维持 live rendering
- audio session 冲突

这部分才是真正的高难度功能。

---

## 10. 实机验收顺序

建议固定用这套，不要随机点：

| 阶段 | 测试 | 通过条件 |
|---|---|---|
| A | 安装 + Respring | 正常进桌面，无黑屏/循环 Respring |
| B | 等 8 秒 | 日志出现 `BOOT-OK` |
| C | 设置页 | `设置 -> SplitWindow` 可打开 |
| D | App 白名单 | 可选 Calculator / Notes |
| E | 显式启用 | 不崩 SpringBoard |
| F | 悬浮按钮 | 能显示/拖动 |
| G | 边缘手势 | 能打开面板 |
| H | Calculator Scene | 显示真实可交互 Scene |
| I | 替换 App | Notes 替换 Calculator |
| J | 连续开关 20 次 | SpringBoard 不崩 |
| K | 键盘 | Notes 输入框能弹键盘并输入 |
| L | 底层视频 | 小窗存在时底层视频继续更新至少 30 秒 |

---

## 11. 当前已知技术风险

按优先级：

1. **SpringBoard 生命周期/黑屏**
2. **RootHide relocation / 注入兼容**
3. **iOS 16 FrontBoard 私有 selector 差异**
4. **Scene foreground/visibility 被系统回收**
5. **第二次打开同 App Scene 的生命周期问题**
6. **小窗 touch coordinate / transform**
7. **keyboard focus**
8. **底层 App 实时运行的 RunningBoard assertion**
9. **AudioSession / Camera / DRM 等系统资源冲突**

不要假装这些已经解决。

---

## 12. 当前版本历史（重要节点）

```text
c628526  first commit
3fc1491  fix: add safe RootHide startup and file logging
5a3d1db  fix: rebase SplitWindow on known-good RootHide compatibility path
6f5c8fb  fix: build native RootHide arm64 arm64e package
```

当前以 `6f5c8fb` 为基线继续。

不要回退到早期会自动启动 overlay 的版本。

---

## 13. 用户偏好的工作方式

新会话请遵守：

- 用户希望我们**直接动代码**，不是只讲方案。
- 优先复用 demo/开源项目，不喜欢无依据重新发明架构。
- 遇到不确定不要猜；先查项目、查日志、查现有实现。
- 一次解决一个真正的根因，不要在错误方向堆补丁。
- 后续版本最好：

```text
改代码
-> commit
-> push GitHub
-> GitHub Actions
-> 下载 deb
-> 直接把 deb 给用户
```

- 用户不想再自己手工传 ZIP/拼工作流。
- 对 SpringBoard 安全性极其敏感，因为已经发生过一次黑屏事故。

---

## 14. 新会话建议直接用的开场执行指令

可以直接按下面执行，不用重新问需求：

> 打开 `Dream-zhc/SplitWindow-RootHide-PoC`，以 `main` 的 `6f5c8fb` 为当前基线。先检查 GitHub Actions 最新构建。不要改需求、不要重构 UI、不要恢复启动时自动创建 UIWindow/FBScene。第一目标是让 native RootHide `arm64 + arm64e` 包稳定构建并下载 `.deb`；第二目标是安装后 SpringBoard 安全启动并产出 `/var/mobile/SplitWindow/logs/splitwindow.log`。只有安全启动通过以后，才逐级测试 preferences -> overlay -> FBScene -> touch -> keyboard -> 底层 App live rendering。任何失败先找最前面的共同根因，不要用截图/镜像冒充真实 Scene Hosting。

---

## 15. 最重要的一句话

**先保证“装上不会把 SpringBoard 打黑”，再谈小窗功能。**

这是这个项目当前不可跨越的优先级。
