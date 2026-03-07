#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, Optional

from epub_indexer import (
    DEFAULT_DB_PATH as INDEXER_DEFAULT_DB_PATH,
    DEFAULT_DOC_DIR as INDEXER_DEFAULT_DOC_DIR,
    find_class,
    find_examples,
    find_method,
    find_property,
    get_chunk,
    rebuild_index,
    search_index,
    suggest_api_for_task,
)


DEFAULT_DOC_DIR = Path(
    os.environ.get("GODOT_EPUB_DOC_DIR", str(INDEXER_DEFAULT_DOC_DIR))
).resolve()
DEFAULT_DB_PATH = Path(
    os.environ.get("GODOT_EPUB_INDEX_PATH", str(INDEXER_DEFAULT_DB_PATH))
).resolve()


SERVER_NAME = "godot-epub-docs"
SERVER_VERSION = "0.1.0"
DEBUG_LOG = os.environ.get("GODOT_EPUB_MCP_DEBUG_LOG", "").strip()
IO_MODE = "header-json"


def debug_log(message: str) -> None:
    if not DEBUG_LOG:
        return
    try:
        Path(DEBUG_LOG).parent.mkdir(parents=True, exist_ok=True)
        with open(DEBUG_LOG, "a", encoding="utf-8") as f:
            f.write(message + "\n")
    except Exception:
        pass


def write_message(payload: Dict[str, Any]) -> None:
    raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    if IO_MODE == "line-json":
        sys.stdout.buffer.write(raw + b"\n")
    else:
        sys.stdout.buffer.write(f"Content-Length: {len(raw)}\r\n\r\n".encode("ascii"))
        sys.stdout.buffer.write(raw)
    sys.stdout.buffer.flush()
    debug_log(f"send({IO_MODE})")


def read_message() -> Optional[Dict[str, Any]]:
    global IO_MODE
    first_line = sys.stdin.buffer.readline()
    if not first_line:
        return None

    stripped = first_line.strip()
    if stripped.startswith(b"{"):
        IO_MODE = "line-json"
        buffer = first_line
        while True:
            try:
                payload = json.loads(buffer.decode("utf-8"))
                debug_log(f"recv(line-json): {payload.get('method', '')}")
                return payload
            except json.JSONDecodeError:
                next_line = sys.stdin.buffer.readline()
                if not next_line:
                    return None
                buffer += next_line

    headers: Dict[str, str] = {}
    IO_MODE = "header-json"
    line = first_line
    while True:
        if line in (b"\r\n", b"\n"):
            break
        key, _, value = line.decode("utf-8", errors="ignore").partition(":")
        headers[key.strip().lower()] = value.strip()
        line = sys.stdin.buffer.readline()
        if not line:
            return None

    content_length = int(headers.get("content-length", "0"))
    if content_length <= 0:
        return None

    body = sys.stdin.buffer.read(content_length)
    if not body:
        return None

    payload = json.loads(body.decode("utf-8"))
    debug_log(f"recv(header-json): {payload.get('method', '')}")
    return payload


def ok_response(req_id: Any, result: Dict[str, Any]) -> Dict[str, Any]:
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def err_response(req_id: Any, code: int, message: str) -> Dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {
            "code": code,
            "message": message,
        },
    }


def format_hits_text(hits) -> str:
    if not hits:
        return "No matches found in indexed EPUB docs."

    lines = []
    for i, hit in enumerate(hits, start=1):
        lines.append(f"[{i}] chunk_id={hit['chunk_id']} score={hit['score']}")
        lines.append(f"  file: {hit['epub_file']}::{hit['path']}")
        meta = []
        if hit["heading"]:
            meta.append(f"heading={hit['heading']}")
        if hit["class_name"]:
            meta.append(f"class={hit['class_name']}")
        if hit["method_name"]:
            meta.append(f"method={hit['method_name']}")
        if meta:
            lines.append("  " + " | ".join(meta))
        lines.append("  " + hit["snippet"].replace("\n", " "))
    return "\n".join(lines)


def tool_search_docs(args: Dict[str, Any]) -> Dict[str, Any]:
    query = str(args.get("query", "")).strip()
    if not query:
        return {
            "content": [{"type": "text", "text": "Missing required argument: query"}],
            "isError": True,
        }

    limit = int(args.get("limit", 8))
    class_name = args.get("class_name")
    method_name = args.get("method_name")

    hits = search_index(
        index_path=DEFAULT_DB_PATH,
        query=query,
        limit=limit,
        class_name=str(class_name) if class_name else None,
        method_name=str(method_name) if method_name else None,
    )
    return {"content": [{"type": "text", "text": format_hits_text(hits)}]}


def tool_get_chunk(args: Dict[str, Any]) -> Dict[str, Any]:
    raw_id = args.get("chunk_id")
    if raw_id is None:
        return {
            "content": [
                {"type": "text", "text": "Missing required argument: chunk_id"}
            ],
            "isError": True,
        }

    try:
        chunk_id = int(raw_id)
    except (TypeError, ValueError):
        return {
            "content": [{"type": "text", "text": "chunk_id must be an integer"}],
            "isError": True,
        }

    item = get_chunk(DEFAULT_DB_PATH, chunk_id)
    if not item:
        return {
            "content": [{"type": "text", "text": f"Chunk not found: {chunk_id}"}],
            "isError": True,
        }

    text = (
        f"chunk_id={item['chunk_id']}\n"
        f"epub={item['epub_file']}\n"
        f"path={item['path']}\n"
        f"title={item['title']}\n"
        f"heading={item['heading']}\n"
        f"class={item['class_name']}\n"
        f"method={item['method_name']}\n"
        "---\n"
        f"{item['text']}"
    )
    return {"content": [{"type": "text", "text": text}]}


def tool_rebuild_index(args: Dict[str, Any]) -> Dict[str, Any]:
    doc_dir = Path(str(args.get("doc_dir", DEFAULT_DOC_DIR))).resolve()
    force = bool(args.get("force", False))
    try:
        stats = rebuild_index(doc_dir=doc_dir, index_path=DEFAULT_DB_PATH, force=force)
    except Exception as exc:
        return {
            "content": [{"type": "text", "text": f"Failed to rebuild index: {exc}"}],
            "isError": True,
        }

    lines = ["Index rebuilt successfully."]
    for k, v in stats.items():
        lines.append(f"- {k}: {v}")
    return {"content": [{"type": "text", "text": "\n".join(lines)}]}


def tool_find_class(args: Dict[str, Any]) -> Dict[str, Any]:
    class_name = str(args.get("class_name", "")).strip()
    if not class_name:
        return {
            "content": [
                {"type": "text", "text": "Missing required argument: class_name"}
            ],
            "isError": True,
        }
    item = find_class(DEFAULT_DB_PATH, class_name)
    if not item:
        return {
            "content": [{"type": "text", "text": f"Class not found: {class_name}"}],
            "isError": True,
        }
    lines = [f"class={item['class_name']}", f"path={item['path']}"]
    if item["inherits"]:
        lines.append(f"inherits={item['inherits']}")
    if item["inherited_by"]:
        lines.append(f"inherited_by={item['inherited_by']}")
    if item["description"]:
        lines.append(item["description"])
    return {"content": [{"type": "text", "text": "\n".join(lines)}]}


def tool_find_method(args: Dict[str, Any]) -> Dict[str, Any]:
    class_name = str(args.get("class_name", "")).strip()
    method_name = str(args.get("method_name", "")).strip()
    if not class_name or not method_name:
        return {
            "content": [
                {
                    "type": "text",
                    "text": "Missing required arguments: class_name and method_name",
                }
            ],
            "isError": True,
        }
    items = find_method(DEFAULT_DB_PATH, class_name, method_name)
    if not items:
        return {
            "content": [
                {
                    "type": "text",
                    "text": f"Method not found: {class_name}.{method_name}",
                }
            ],
            "isError": True,
        }
    lines = []
    for idx, item in enumerate(items, start=1):
        lines.append(f"[{idx}] {item['class_name']}.{item['method_name']}")
        lines.append(f"  signature: {item['signature']}")
        lines.append(f"  path: {item['path']}")
        if item["description"]:
            lines.append(f"  {item['description']}")
    return {"content": [{"type": "text", "text": "\n".join(lines)}]}


def tool_find_property(args: Dict[str, Any]) -> Dict[str, Any]:
    class_name = str(args.get("class_name", "")).strip()
    property_name = str(args.get("property_name", "")).strip()
    if not class_name or not property_name:
        return {
            "content": [
                {
                    "type": "text",
                    "text": "Missing required arguments: class_name and property_name",
                }
            ],
            "isError": True,
        }
    item = find_property(DEFAULT_DB_PATH, class_name, property_name)
    if not item:
        return {
            "content": [
                {
                    "type": "text",
                    "text": f"Property not found: {class_name}.{property_name}",
                }
            ],
            "isError": True,
        }
    lines = [
        f"property={item['class_name']}.{item['property_name']}",
        f"type={item['type_name']}",
        f"setter={item['setter_name']}",
        f"getter={item['getter_name']}",
        f"default={item['default_value']}",
        f"path={item['path']}",
    ]
    if item["description"]:
        lines.append(item["description"])
    return {"content": [{"type": "text", "text": "\n".join(lines)}]}


def tool_find_examples(args: Dict[str, Any]) -> Dict[str, Any]:
    query = str(args.get("query", "")).strip()
    if not query:
        return {
            "content": [{"type": "text", "text": "Missing required argument: query"}],
            "isError": True,
        }
    limit = int(args.get("limit", 3))
    class_name = args.get("class_name")
    method_name = args.get("method_name")
    items = find_examples(
        DEFAULT_DB_PATH,
        query=query,
        limit=limit,
        class_name=str(class_name) if class_name else None,
        method_name=str(method_name) if method_name else None,
    )
    if not items:
        return {
            "content": [{"type": "text", "text": "No examples found."}],
            "isError": True,
        }
    lines = []
    for i, item in enumerate(items, start=1):
        lines.append(
            f"[{i}] example_id={item['example_id']} path={item['path']} heading={item['heading']} lang={item['language']}"
        )
        if item["class_name"] or item["method_name"]:
            lines.append(f"  class={item['class_name']} method={item['method_name']}")
        lines.append("  ```")
        lines.append(item["code"])
        lines.append("  ```")
    return {"content": [{"type": "text", "text": "\n".join(lines)}]}


def tool_suggest_api_for_task(args: Dict[str, Any]) -> Dict[str, Any]:
    task = str(args.get("task", "")).strip()
    if not task:
        return {
            "content": [{"type": "text", "text": "Missing required argument: task"}],
            "isError": True,
        }
    limit = int(args.get("limit", 6))
    items = suggest_api_for_task(DEFAULT_DB_PATH, task=task, limit=limit)
    if not items:
        return {
            "content": [{"type": "text", "text": "No API suggestions found."}],
            "isError": True,
        }
    lines = ["Likely APIs for this task:"]
    for i, item in enumerate(items, start=1):
        lines.append(
            f"[{i}] class={item['class_name']} method={item['method_name']} path={item['path']}"
        )
        lines.append(f"  reason: {item['reason']}")
    return {"content": [{"type": "text", "text": "\n".join(lines)}]}


TOOLS = [
    {
        "name": "search_docs",
        "description": "Search EPUB documentation chunks by keyword, class and method hints.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search terms, e.g. Node add_child signal",
                },
                "limit": {"type": "integer", "minimum": 1, "maximum": 50, "default": 8},
                "class_name": {
                    "type": "string",
                    "description": "Optional exact class filter",
                },
                "method_name": {
                    "type": "string",
                    "description": "Optional exact method filter",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "get_chunk",
        "description": "Fetch full text of a search result chunk by chunk_id.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "chunk_id": {"type": "integer"},
            },
            "required": ["chunk_id"],
        },
    },
    {
        "name": "rebuild_index",
        "description": "Re-index all EPUB files in the docs directory into local SQLite FTS.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "doc_dir": {
                    "type": "string",
                    "description": "Directory containing .epub files",
                },
                "force": {"type": "boolean", "default": False},
            },
        },
    },
    {
        "name": "find_class",
        "description": "Get class reference details (description, inheritance, source path).",
        "inputSchema": {
            "type": "object",
            "properties": {"class_name": {"type": "string"}},
            "required": ["class_name"],
        },
    },
    {
        "name": "find_method",
        "description": "Get method signatures and descriptions by class + method.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "class_name": {"type": "string"},
                "method_name": {"type": "string"},
            },
            "required": ["class_name", "method_name"],
        },
    },
    {
        "name": "find_property",
        "description": "Get property details (type, getter/setter, default, description).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "class_name": {"type": "string"},
                "property_name": {"type": "string"},
            },
            "required": ["class_name", "property_name"],
        },
    },
    {
        "name": "find_examples",
        "description": "Find code examples by query with optional class/method filters.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "limit": {"type": "integer", "minimum": 1, "maximum": 20, "default": 3},
                "class_name": {"type": "string"},
                "method_name": {"type": "string"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "suggest_api_for_task",
        "description": "Suggest likely Godot classes/methods for a task description.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "task": {"type": "string"},
                "limit": {"type": "integer", "minimum": 1, "maximum": 20, "default": 6},
            },
            "required": ["task"],
        },
    },
]


def handle_request(req: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    method = req.get("method")
    req_id = req.get("id")

    if method == "initialize":
        return ok_response(
            req_id,
            {
                "protocolVersion": req.get("params", {}).get(
                    "protocolVersion", "2024-11-05"
                ),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            },
        )

    if method == "tools/list":
        return ok_response(req_id, {"tools": TOOLS})

    if method == "tools/call":
        params = req.get("params", {})
        tool_name = params.get("name")
        args = params.get("arguments", {}) or {}

        if tool_name == "search_docs":
            return ok_response(req_id, tool_search_docs(args))
        if tool_name == "get_chunk":
            return ok_response(req_id, tool_get_chunk(args))
        if tool_name == "rebuild_index":
            return ok_response(req_id, tool_rebuild_index(args))
        if tool_name == "find_class":
            return ok_response(req_id, tool_find_class(args))
        if tool_name == "find_method":
            return ok_response(req_id, tool_find_method(args))
        if tool_name == "find_property":
            return ok_response(req_id, tool_find_property(args))
        if tool_name == "find_examples":
            return ok_response(req_id, tool_find_examples(args))
        if tool_name == "suggest_api_for_task":
            return ok_response(req_id, tool_suggest_api_for_task(args))
        return err_response(req_id, -32601, f"Unknown tool: {tool_name}")

    if method == "ping":
        return ok_response(req_id, {})

    if req_id is None:
        return None
    return err_response(req_id, -32601, f"Method not found: {method}")


def main() -> None:
    debug_log("godot-epub-docs server started")
    while True:
        request = read_message()
        if request is None:
            debug_log("stdin closed")
            break
        response = handle_request(request)
        if response is not None:
            write_message(response)


if __name__ == "__main__":
    main()
