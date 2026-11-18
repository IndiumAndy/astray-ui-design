#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
bundle="$PWD/.build/MCP/UIDesignMCP.app"
binary="$bundle/Contents/MacOS/UIDesignMCP"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
ln -sfn "$PWD/Runtime" "$bundle/Contents/Resources/Runtime"
swiftc -swift-version 6 -o "$binary" \
  Tools/UIDesignMCP/main.swift Sources/DesignDocument/CanvasBridge.swift \
  Sources/DesignDocument/DesignBatch.swift Sources/DesignDocument/DesignCodec.swift \
  Sources/DesignDocument/DesignLayout.swift Sources/DesignDocument/DesignProject.swift \
  Sources/DesignDocument/ContactExample.swift Sources/DesignDocument/ReviewDevice.swift \
  Sources/Export/ExportSelection.swift Sources/Export/ExportUpdate.swift Sources/Export/ProjectExport.swift \
  Runtime/Phone/Sources/RuntimeBehavior.swift Runtime/Phone/Sources/RuntimeDesign.swift \
  Runtime/Phone/Sources/ScreenLayout.swift
printf '%s\n' "$binary"
