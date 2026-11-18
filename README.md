# UI Design

原生 macOS SwiftUI 工作台。可在画板上拖放组件、修改精确坐标并保存设计。可在 iPhone 模拟器和默认浏览器中运行同一份设计，并导出 SwiftUI 和 React/Astryx 源码。支持参考布局、设备覆盖、固定栏、共享按钮样式，以及页面事件、表单校验和宿主数据。

## 启动与构建

在 Finder 双击 `UIDesign.xcodeproj`。在 Xcode 选择共享方案 `UIDesign` 和运行目标 `My Mac`，按 ⌘R。

```sh
xcodebuild -project UIDesign.xcodeproj -scheme UIDesign \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData build

open .build/DerivedData/Build/Products/Debug/UIDesign.app
```

工程最低目标为 macOS 15.0，使用 Swift 6。此次在 macOS 26.3、Xcode 26.6（17F113）的 Apple Silicon Mac 上验证。增加编辑器文件、目标或修改构建配置后，用 XcodeGen 2.46.0 执行 `xcodegen generate`。调整 iPhone 模板中的文件后，再执行 `xcodegen generate --spec Runtime/Phone/project.yml`。日常打开、构建和测试使用 Xcode 即可。

## 编辑与保存

- 从左栏拖入标题、输入框、按钮或设置项。也可点按组件，或按 ⌘F 搜索后按回车插入。
- 滚动或按住空格拖动画布。双指捏合缩放，也可用工具栏百分比切换倍率并重新适应窗口。吸附开关位于缩放右侧。
- 单击选择组合，双击进组，⌘ 单击直达子控件。双击文字、或选中文字图层后按回车可编辑。回车提交，Esc 放弃草稿。选中图层后可用方向键微移，⇧ 方向键以 10 pt 为单位移动，⌥ 方向键切换图层。
- 拖拽选框四角改尺寸。拖动组内间距手柄改间距。检查器也可输入位置、宽高与间距，或调整开关。⌥⌘I 收放检查器，⌘Z 撤销，⇧⌘Z 重做。
- 首次按 ⌘S 选择名称和文件夹。存盘后的编辑会自动写回 `.uidesign`。也可用 ⌘O、「打开最近使用」或 Finder 双击重新打开。⌘N 单独建立空白项目。
- ⌥⌘2 和 ⌥⌘3 查看阶段 0 的设置和连线样稿，⌥⌘1 返回当前项目。

## 运行联系人示例

1. 在 Xcode 运行编辑器。选「文件 → 新建联系人示例」，在侧栏「页面」里打开「联系人」。
2. 选「运行 → 在 iPhone 模拟器运行」。点联系人姓名进入详情，可在面板内点按、滑动和输入。右上角可收起面板。
3. 回到「联系人」画板，选「运行 → 在默认浏览器运行」。打开同一条记录并输入昵称。切换画布到「联系人详情」，挪动保存按钮，松手后两端更新。
4. 选「运行 → 导出源码」，填写新文件夹名称。导出目录的 README 标明独立构建方式及保存回调位置。

模拟器预览需要完整 Xcode、支持 iPhone 17 Pro 的 iOS 模拟器运行时，以及 [AXe 2.0.4](https://github.com/cameroncooke/AXe/releases/tag/v2.0.4)。编辑器使用名为 `UI Design Stage 2` 的专用模拟器。AXe 可以位于 PATH、`UIDESIGN_AXE` 指定的路径，或 `~/Library/Application Support/UI Design/Tools/AXe/axe`。使用发布页的通用压缩包时，把整个包解压到该目录，以保留同级 Frameworks。模拟器画面按帧传输，拖动松手后会发送一次滑动。

Web 预览需要 Node.js 22.12 或更新版本及 npm。首次打开时会根据锁文件安装并构建 React 和 Astryx。Web 和 iPhone 预览从编辑器的本机回环地址读取已提交的画板，导出工程自带独立的数据和源码。项目格式为版本 4。打开版本 1 至 3 的文件时会保留页面和图层标识。

## 布局与设备适配

- 打开工具栏的「画板设置」，选择手机、平板或桌面，或直接输入宽高。这里也可以选比例、交换宽高、展开整页，或添加参考布局和对照底图。
- 按住 ⇧ 点选多个顶层图层，再用检查器的「排列」设为纵排、横排或网格。双击组合进入，⌘ 单击可直达子控件。子项可拖动重排，或在检查器输入目标序号。
- 检查器中分别设置宽度和高度。拖动选框只会把改动的轴切换为「固定值」。给高度为「随内容」的输入框添加「提示文字」，排列会为新内容腾出空间。
- 在「画板设置」切换到「仅改手机布局」等设备范围。设备可有不同排列与顺序，控件名称和提示继续共享。「恢复通用布局」清除当前画板在该设备范围的覆盖。
- 选中顶层组件，从检查器的「滚动」设为固定顶栏或底栏。「展开整页」保留首屏边界。运行时可滚动中间内容。
- 在按钮检查器新建或选择项目样式。先调整单个按钮的高度或圆角，再用「更新样式」同步引用者。

[布局验收样例](docs/stage-3/布局验收样例.uidesign)包含登录、长设置页和联系人流程。[阶段 3 验收记录](docs/stage-3/验收记录.md)记录复测结果。

## 页面连线与交互

- 选中按钮、列表行或联系人列表，把右侧连接点拖到目标画板。按住 ⌥ 放开可设为弹出面板，也可在检查器点「设置事件」或用 ⌥L 指定动作。拖动画板标题可调整流程图位置。在缩放菜单选「查看全部画板」。
- 在字段检查器选「由应用传入」或「由列表行传入」，填写字段键和示例值。给字段和提交按钮填入同一个表单名称，再设置具名动作。可启用必填、长度和邮箱校验。搜索与开关可通过「值改变时」直接报送新值。
- 在「配置列表…」设定数据键、行字段、行高和示例数据。用「预览状态」检查有数据、空数据、加载中和加载失败。空态按钮可连接到另一页。
- 选「文件 → 新建交互示例」，或打开[交互验收样例](docs/stage-4/交互验收样例.uidesign)。在通讯录进入设置、打开关于面板，或点联系人进入详情。导出的 README 说明宿主数据和动作入口。

## 测试与验收

```sh
xcodebuild -project UIDesign.xcodeproj -scheme UIDesign \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData test
```

[阶段 4 验收记录](docs/stage-4/验收记录.md)包含交互、宿主和双端测试。[阶段 2 验收记录](docs/stage-2/验收记录.md)包含双端运行、刷新样本和独立导出的结果。[阶段 1 验收记录](docs/stage-1/验收记录.md)包含实测结果、画面和亲手试用步骤。[阶段 0 设计评审](docs/stage-0/设计评审.md)保留了原工作台样稿。

## 代码职责

| 领域 | 当前入口 | 职责 |
| --- | --- | --- |
| 设计文档 | `Sources/DesignDocument/` | 保存格式版本、画板、组件层级和稳定标识。通过原生文档系统读写、撤销与自动保存 |
| 编辑器 | `Sources/Editor/` | 组件与图层侧栏、画布坐标、选择、拖放和检查器。已提交的编辑写入同一份设计文档 |
| 样稿 | `Sources/DesignReview/`、`Sources/Components/ReviewPages.swift` | 阶段 0 设置与连线评审 |
| 组件 | `Sources/Components/` | 画布与手机预览共用的 SwiftUI 控件 |
| 预览 | `Sources/Preview/`、`Sources/Runtime/` | iPhone 模拟器帧和输入、默认浏览器运行及文档更新 |
| 导出 | `Sources/Export/`、`Runtime/` | SwiftUI 和 React/Astryx 工程模板，以及页面控件和事件入口的生成 |

SwiftUI 控件参照 Astryx 的字号、间距和圆角实现。[Meta Astryx 参考修订](https://github.com/meta/astryx/tree/be5d290db9f03921256b6b4a2628cfde4f7cb192/packages/native/apple)
