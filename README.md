# UI Design

原生 macOS SwiftUI 工作台。阶段 1 从空白 iPhone 画板开始，可拖放组件、修改组合与精确坐标，并将设计保存为本地项目。

## 启动与构建

在 Finder 双击 `UIDesign.xcodeproj`。在 Xcode 选择共享方案 `UIDesign` 和运行目标 `My Mac`，按 ⌘R。

```sh
xcodebuild -project UIDesign.xcodeproj -scheme UIDesign \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData build

open .build/DerivedData/Build/Products/Debug/UIDesign.app
```

工程最低目标为 macOS 15.0，使用 Swift 6。此次在 macOS 26.3、Xcode 26.6（17F113）的 Apple Silicon Mac 上验证。增加文件、目标或修改构建配置后，用 XcodeGen 2.46.0 执行 `xcodegen generate`。日常打开、构建和测试使用 Xcode 即可。

## 编辑与保存

- 从左栏拖入标题、输入框、按钮或设置项。也可点按组件，或按 ⌘F 搜索后按回车插入。
- 滚动或按住空格拖动画布。双指捏合缩放，也可用工具栏百分比切换倍率并重新适应窗口。吸附开关位于缩放右侧。
- 单击选择组合，双击进组，⌘ 单击直达子控件。双击文字、或选中文字图层后按回车可编辑。回车提交，Esc 放弃草稿。选中图层后可用方向键微移，⇧ 方向键以 10 pt 为单位移动，⌥ 方向键切换图层。
- 拖拽选框四角改尺寸。拖动组内间距手柄改间距。检查器也可输入位置、宽高与间距，或调整开关。⌥⌘I 收放检查器，⌘Z 撤销，⇧⌘Z 重做。
- 首次按 ⌘S 选择名称和文件夹。存盘后的编辑会自动写回 `.uidesign`。也可用 ⌘O、「打开最近使用」或 Finder 双击重新打开。⌘N 单独建立空白项目。
- ⌥⌘2 和 ⌥⌘3 查看阶段 0 的设置和连线样稿，⌥⌘1 返回当前项目。

## 测试与验收

```sh
xcodebuild -project UIDesign.xcodeproj -scheme UIDesign \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData test
```

[阶段 1 验收记录](docs/stage-1/验收记录.md)包含实测结果、画面和亲手试用步骤。[阶段 0 设计评审](docs/stage-0/设计评审.md)保留了原工作台样稿。

## 代码职责

| 领域 | 当前入口 | 职责 |
| --- | --- | --- |
| 设计文档 | `Sources/DesignDocument/` | 保存格式版本、画板、组件层级和稳定标识。通过原生文档系统读写、撤销与自动保存 |
| 编辑器 | `Sources/Editor/` | 组件与图层侧栏、画布坐标、选择、拖放和检查器。已提交的编辑写入同一份设计文档 |
| 样稿 | `Sources/DesignReview/`、`Sources/Components/ReviewPages.swift` | 阶段 0 设置与连线评审 |
| 组件 | `Sources/Components/` | 画布与手机预览共用的 SwiftUI 控件 |
| 预览 | `Sources/Preview/` | 当前项目或样稿的 iPhone 外观预览。阶段 2 接入模拟器与浏览器 |
| 导出与 MCP | 分阶段计划 | 后续读取同一份文档并复用编辑逻辑 |

SwiftUI 控件参照 Astryx 的字号、间距和圆角实现。[Meta Astryx 参考修订](https://github.com/meta/astryx/tree/be5d290db9f03921256b6b4a2628cfde4f7cb192/packages/native/apple)
