# SplitWindow PoC — iOS 16 / Dopamine RootHide

> v0.3.1 builds with the official `roothide/theos` fork and
> `THEOS_PACKAGE_SCHEME=roothide`. The build is pinned to the patched iOS 16.5
> SDK with an iOS 16.0 deployment target and only produces arm64/arm64e slices.

一个用于验证 **真实 App Scene 悬浮小窗** 的最小 Theos tweak 工程。

## 第一版范围

- iOS 16.x，Dopamine + RootHide。
- SpringBoard 注入，不要求修改目标 App。
- 右侧屏幕边缘向内滑：打开 App 面板。
- 全局悬浮按钮：备用/调试入口。
- 设置 App -> SplitWindow -> 选择允许出现在面板中的 App。
- 同时只保留一个小窗；新小窗替换旧小窗。
- 小窗固定约 72% 屏幕比例，可拖动、关闭。
- 小窗内使用真实 App Scene，不是截图/镜像。
- 目标：触摸、滑动、文本输入真实可交互。
- 底层原 App 不执行“切后台”激活流程，目标是继续保持实时刷新。
- 第一版只验收竖屏。

## Scene Host 策略

1. 用 SpringBoard 私有 `launchApplicationWithIdentifier:suspended:` 启动目标 App，但不做普通全屏激活。
2. 从 `FBSceneManager` 找到目标 App 的 scene。
3. 将 scene 的 mutable settings 标记为 foreground / not backgrounded。
4. 优先使用 `scene.uiPresentationManager -> createPresenterWithIdentifier -> presentationView`。
5. 如果 presenter API 不可用，fallback 到 `_UISceneLayerHostContainerView`。
6. 关闭时 deactivate/invalidate presenter，并把目标 scene 恢复 background。

这条路线参考了 Konban、Zetsu 的 Scene Hosting 思路，以及较新的 FrontBoardAppLauncher / LiveContainer 多任务研究；本工程没有直接复制它们的源码。

## GitHub Actions 构建

直接把整个目录上传到 GitHub，默认分支为 `main` 或 `master`。

Actions -> `Build RootHide DEB` -> Run workflow。

构建成功后下载 Artifact `SplitWindow-RootHide-DEB`，里面是 `.deb`。

工作流使用 GitHub macOS runner + 固定版本 Theos。本地仍不需要安装 Xcode。
上传 artifact 前会校验 deb architecture、Mach-O slices、动态库依赖和 tweak filter。

## 安装

用 Sileo / Zebra / Filza 安装 Actions 生成的 RootHide `.deb`，然后 respring。

首次安装后：

1. 打开 **设置 -> SplitWindow**。
2. 打开“启用”。
3. 进入“选择小窗 App”，勾选 Calculator / Notes 或你要测试的 App。
4. 回到桌面或任意 App。
5. 从最右侧向左滑，或点悬浮按钮。
6. 点一个 App。

## 日志

如果黑屏、SpringBoard crash、点击无反应，先采集：

```sh
/rootfs/usr/bin/log stream --style compact --level debug \
  --predicate 'eventMessage CONTAINS "[SplitWindow]"'
```

重点看：

- `launch requested`
- `found scene`
- `using uiPresentationManager presenter`
- `using _UISceneLayerHostContainerView fallback`
- `open failed`

## 当前故意不做

- 横屏。
- 自由缩放。
- 多个并行小窗。
- 真正 50/50 split view。
- 手势冲突高级仲裁。
- App 图标美化。
- 锁屏/通知中心场景适配。

## 高风险点

- iOS 私有 Scene API 在不同 16.x build 上可能有 selector / settings 差异。
- 键盘焦点是 Scene Hosting 的历史难点，必须实机测试，不能只以“画面显示”为成功。
- 某些 single-scene App、相机、DRM/受保护内容可能黑屏或拒绝被 rehost。
- RootHide 环境下 PreferenceLoader / SpringBoard tweak injection 需要实际设备确认。

