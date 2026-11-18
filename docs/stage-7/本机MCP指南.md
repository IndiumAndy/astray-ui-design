# 通过本机 MCP 编辑设计

从项目目录执行以下两条命令。构建不安装额外工具，需要 Xcode 自带 Swift 6。

    Tools/build-mcp.sh
    python3 Tools/test-mcp.py

第一条给出客户端应启动的可执行文件。在你选用的 MCP 客户端添加 stdio 服务，启动参数为：

    --project /绝对路径/设计.uidesign --exports /绝对路径/导出

不需要导出时可省略 --exports。服务只操作启动时选定的单个项目，不接收新的项目路径，不监听网络。导出只允许在指定的已有目录下新建子目录，拒绝覆盖。编辑器打开该文档时，先在当前窗口的「工作台」菜单勾选「允许本机 MCP」；关闭窗口结束许可。未打开时直接修改已保存的本地文档，因此不会加入某个 App 窗口的撤销历史。

| 工具 | 用法 |
| --- | --- |
| canvas_read | 返回项目、页面与图层标识及 revision，省略图片二进制。 |
| canvas_apply | 提供 page、刚读取的 revision 和 operations。支持改文字（text）、自由摆放中左对齐同组图层（align）、调整容器间距（gap）。有效批次一次提交，一项无效则整批不写。 |
| preview_simulator | 给当前内嵌 iPhone 发 screenshot、tap、swipe、text，响应含实际画面的 PNG。点按与滑动用 402 × 874 pt 坐标；在编辑器先打开内嵌预览。 |
| canvas_export | 提供 name、revision 和可选的 pages。使用工作台同一套生成逻辑。 |

例如把三个同级图层左对齐、并把一个纵排容器的间距改为 16：

    {
      "page": "页面 UUID",
      "revision": "canvas_read 返回的 revision",
      "operations": [
        {"kind":"align","ids":["第一项 UUID","第二项 UUID","第三项 UUID"]},
        {"kind":"gap","ids":["纵排容器 UUID"],"value":16}
      ]
    }

如果读到修订冲突，先重新读取并比对，而不是用新 revision 强行重发旧命令。若客户端超时而编辑器未确认，先重新读取核对结果再重试，避免重复操作。可在编辑器按 ⌘Z 撤销打开文档时由 MCP 做的一整批编辑。

协议参考：[MCP stdio](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#stdio)、[生命周期](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)、[工具](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)。
