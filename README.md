# UI Design

原生 macOS SwiftUI 工作台。阶段 0 提供 Xcode 工程和三套可切换的设计稿。启动时进入空白画板。

## 启动与构建

在 Finder 双击 `UIDesign.xcodeproj`。在 Xcode 选择共享方案 `UIDesign` 和运行目标 `My Mac`，按 ⌘R。

```sh
xcodebuild -project UIDesign.xcodeproj -scheme UIDesign \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData build

open .build/DerivedData/Build/Products/Debug/UIDesign.app
```

工程最低目标为 macOS 15.0，使用 Swift 6 语言模式。本次使用 macOS 26.3、Xcode 26.6（17F113）及 Swift 6.3.3 在 Apple Silicon 上验证。应用依赖系统 SwiftUI 和 SF Symbols，使用本地临时签名，可直接构建和运行。

`project.yml` 定义工程配置。增加目标或修改构建配置后，使用 XcodeGen 2.46.0 执行 `xcodegen generate`，提交配置与生成的工程及共享方案。日常打开、运行和构建只需要 Xcode。

设计稿中的控件为本地 SwiftUI 样例，参照 Astryx 的字号、间距和圆角。后续接入组件运行库时锁定实际使用的版本及依赖树。[Meta Astryx 参考修订](https://github.com/meta/astryx/tree/be5d290db9f03921256b6b4a2628cfde4f7cb192/packages/native/apple)

## 评审与验证

用菜单栏「设计稿」或 ⌥⌘1、⌥⌘2、⌥⌘3 切换三个状态。用 ⌘F 聚焦组件搜索，⌥⌘I 隐藏或显示右栏，⌘N 返回新建空白画板。工具栏可切换设备尺寸和画布缩放。

[阶段 0 设计稿与验收记录](docs/stage-0/设计评审.md)包含三张原生窗口截图、实际验证结果和后续交互验收项。

## 代码职责

| 领域 | 阶段 0 中的位置 | 后续职责 |
| --- | --- | --- |
| 设计文档 | `Sources/DesignReview/` 持有评审用的临时会话，仅用于切换工作台状态 | 本地项目文件拥有页面、控件、样式、资源和连线。编辑操作和修订属于文档层 |
| 编辑器 | `Sources/App/` 管理窗口与菜单，`Sources/Editor/` 呈现组件库、坐标画布与检查器 | 接收用户操作并提交文档变更。窗口、焦点、工具和选区属于编辑器会话 |
| 组件与导出 | `Sources/Components/` 提供画板和预览共用的样例视图 | 组件层提供控件及组合的定义，导出层读取设计文档、生成可维护的 SwiftUI 和 React/Astryx 源码 |
| 预览 | `Sources/Preview/` 显示固定的 iPhone 设计样例 | 消费已提交的设计修订，处理本机 iPhone 模拟器与浏览器预览的生命周期和事件 |
| MCP | 阶段 7 | 本地 stdio 入口复用文档编辑、预览与导出服务 |

设计原稿的文件格式和保存入口在阶段 1 引入。届时可从保存面板选用自己的应用仓库。阶段 0 的样例随工作台源码维护。
