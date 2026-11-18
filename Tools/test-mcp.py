#!/usr/bin/env python3
"""Exercise the separately built UI Design MCP server over stdio on a test copy."""
import json
import pathlib
import shutil
import subprocess
import tempfile

repo = pathlib.Path(__file__).resolve().parent.parent
binary = repo / ".build/MCP/UIDesignMCP.app/Contents/MacOS/UIDesignMCP"

with tempfile.TemporaryDirectory(prefix="uidesign-mcp-qa-") as directory:
    root = pathlib.Path(directory)
    document = root / "Design.uidesign"
    exports = root / "Exports"
    exports.mkdir()
    shutil.copyfile(repo / "docs/stage-5/个人库验收样例.uidesign", document)
    with subprocess.Popen(
        [str(binary), "--project", str(document), "--exports", str(exports)],
        text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE
    ) as process:
        counter = 0

        def send(method, params=None, notice=False):
            global counter
            counter += 1
            message = {"jsonrpc": "2.0", "method": method}
            if not notice:
                message["id"] = counter
            if params is not None:
                message["params"] = params
            process.stdin.write(json.dumps(message) + "\n")
            process.stdin.flush()
            if not notice:
                reply = json.loads(process.stdout.readline())
                assert reply["id"] == counter, reply
                return reply["result"]

        def call(name, args=None, failure=False):
            reply = send("tools/call", {"name": name, "arguments": args or {}})
            assert reply["isError"] == failure, reply
            return json.loads(reply["content"][0]["text"])

        initialized = send("initialize", {
            "protocolVersion": "2025-11-25", "capabilities": {},
            "clientInfo": {"name": "uidesign-acceptance", "version": "1"},
        })
        assert initialized["protocolVersion"] == "2025-11-25"
        send("notifications/initialized", notice=True)
        assert len(send("tools/list")["tools"]) == 4
        first = call("canvas_read")
        assert first["editorOpen"] is False
        page = first["project"]["page"]
        title, settings = page["layers"][:2]
        group = next(item for item in page["layers"] if item["kind"] == "layout")
        edit = {"page": page["id"], "revision": first["revision"], "operations": [
            {"kind": "align", "ids": [title["id"], settings["id"]], "value": 32},
            {"kind": "gap", "ids": [group["id"]], "value": 16},
        ]}
        new_revision = call("canvas_apply", edit)["revision"]
        assert call("canvas_apply", edit, failure=True)["currentRevision"] == new_revision
        edit["revision"] = new_revision
        edit["operations"].append({"kind": "gap", "ids": [title["id"]], "value": 8})
        assert "第 3 项" in call("canvas_apply", edit, failure=True)["message"]
        latest = call("canvas_read")
        assert latest["revision"] == new_revision
        assert latest["project"]["page"]["layers"][0]["frame"][0][0] == 32
        assert "内嵌" in call("preview_simulator", {"kind": "screenshot"}, failure=True)["message"]
        selection = {"revision": new_revision, "name": "List", "pages": [page["id"]]}
        assert call("canvas_export", selection)["pages"] == ["通讯录"]
        manifest = json.loads((exports / "List/UI Design Export.json").read_text())
        assert len(manifest["pages"]) == 1 and len(manifest["hostLinks"]) == 4
        call("canvas_export", selection, failure=True)
        process.stdin.close()
        assert process.wait(timeout=3) == 0
print("PASS: MCP handshake, edit, conflict, rollback, closed-editor safety, and selected export")
