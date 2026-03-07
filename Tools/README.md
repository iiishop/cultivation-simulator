# EPUB Doc Search Toolkit

This folder contains a local EPUB indexing pipeline plus an MCP server so AI tools can query large documentation without loading the full book into context.

The indexer is tuned for Godot docs: it extracts class metadata, method/property descriptions, and code examples in addition to full-text chunks.

## What it gives you

- `epub_indexer.py`: parses `.epub` files from `../doc`, chunks text, and builds structured + full-text SQLite indexes.
- `epub_mcp_server.py`: stdio MCP server exposing search tools over the indexed docs.
- `epub_index.db`: generated index database (created after first build).

## Quick start

From repository root:

```bash
python Tools/epub_indexer.py build --force
python Tools/epub_indexer.py search "Node add_child signal"
python Tools/epub_indexer.py show 123
python Tools/epub_indexer.py class Node
python Tools/epub_indexer.py method Node add_child
python Tools/epub_indexer.py property Node process_mode
python Tools/epub_indexer.py examples "instantiate scene"
python Tools/epub_indexer.py suggest "spawn enemy scene and attach to root"
```

## MCP setup

Add this MCP server entry to your client config (adjust absolute path):

```json
{
  "mcpServers": {
    "godot-epub-docs": {
      "command": "uv",
      "args": [
        "run",
        "F:/Document/GODOT/cultivation-simulator/Tools/epub_mcp_server.py"
      ],
      "env": {
        "GODOT_EPUB_DOC_DIR": "F:/Document/GODOT/cultivation-simulator/doc",
        "GODOT_EPUB_INDEX_PATH": "F:/Document/GODOT/cultivation-simulator/Tools/epub_index.db",
        "UV_PYTHON_PREFERENCE": "only-managed"
      }
    }
  }
}
```

You can also copy `Tools/mcp.server.example.json` and merge it into your MCP config.

## Exposed MCP tools

- `rebuild_index`
  - Re-index EPUB files from `doc/`.
  - Args: `{ "doc_dir"?: string, "force"?: boolean }`
- `search_docs`
  - Full-text search over chunks with optional class/method filters.
  - Args: `{ "query": string, "limit"?: number, "class_name"?: string, "method_name"?: string }`
- `get_chunk`
  - Fetch complete text for one chunk from search results.
  - Args: `{ "chunk_id": number }`
- `find_class`
  - Find class overview by class name.
  - Args: `{ "class_name": string }`
- `find_method`
  - Find method signatures + description by class and method.
  - Args: `{ "class_name": string, "method_name": string }`
- `find_property`
  - Find property type/getter/setter/default/description.
  - Args: `{ "class_name": string, "property_name": string }`
- `find_examples`
  - Find code snippets from tutorials/doc pages.
  - Args: `{ "query": string, "limit"?: number, "class_name"?: string, "method_name"?: string }`
- `suggest_api_for_task`
  - Given a task description, returns likely class/method candidates.
  - Args: `{ "task": string, "limit"?: number }`

## Optional Skill (systematic Godot workflow)

To guide AI to use this MCP in a consistent, engineering-style flow, use:

- `Tools/skill-godot-epub-mcp/SKILL.md`

This skill defines a fixed pipeline:

1. `suggest_api_for_task`
2. `find_class` / `find_method` / `find_property`
3. `find_examples`
4. `search_docs` + `get_chunk` (only for deep disambiguation)

If your AI client supports local skill loading, register this folder as a skill source and load `godot-epub-mcp-workflow` before coding tasks.

## Suggested usage flow for AI

1. Call `suggest_api_for_task` with the feature intent.
2. Validate candidates with `find_class`, `find_method`, and `find_property`.
3. Pull concrete snippets with `find_examples` and/or `search_docs`.
4. Use `get_chunk` only for deep context on selected hits.
