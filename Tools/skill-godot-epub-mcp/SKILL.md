# Skill: godot-epub-mcp-workflow

Use this skill when implementing, debugging, or reviewing Godot features with the local EPUB MCP server (`godot-epub-docs`).

## Goal

Make Godot coding decisions traceable to local documentation by using a consistent retrieve-verify-implement flow.

## Preconditions

- MCP server `godot-epub-docs` is configured and running.
- Index is built at least once (`rebuild_index` if stale).

## Core Workflow

For any non-trivial Godot task, follow these steps in order.

1. Scope the request
   - Extract required behavior, node lifecycle constraints, and runtime context (tool script, editor plugin, gameplay runtime, networking, physics).

2. Retrieve candidate APIs
   - Call `suggest_api_for_task` with the feature intent.
   - Keep top 3-8 candidates.

3. Validate each key API
   - For each candidate class: call `find_class`.
   - For each candidate method: call `find_method`.
   - For each important property: call `find_property`.

4. Pull implementation examples
   - Call `find_examples` with task keywords and optional class/method filters.
   - If details are still ambiguous, call `search_docs` then `get_chunk` for deep context.

5. Synthesize implementation plan
   - Produce exact node/class/method usage.
   - Include parameter choices and ordering constraints.
   - Mention caveats from docs (thread safety, owner persistence, scene tree timing, etc.).

6. Implement and verify
   - Write code.
   - Re-check against MCP docs for every critical API used.
   - Provide short rationale mapping code decisions to retrieved docs.

## Tool Routing Rules

- If user asks "what class/method should I use?" -> `suggest_api_for_task` first.
- If user gives explicit symbol (`Node.add_child`) -> `find_method` first.
- If user asks about field behavior (`process_mode`) -> `find_property` first.
- If user asks "show me example" -> `find_examples` first.
- If conflicts or uncertainty remain -> `search_docs` + `get_chunk` for authoritative context.

## Output Contract For Coding Answers

When proposing or editing code, include:

- Chosen class/method/property symbols.
- Why each symbol fits this task.
- Any constraints (lifecycle, threading, ownership, persistence).
- Minimal code path to implement now.

## Failure Handling

- If `find_method`/`find_property` returns no result:
  - Retry with exact class casing and nearest base class.
  - Fall back to `search_docs` with symbol-like query.
- If MCP index looks stale:
  - Call `rebuild_index` and rerun lookups.

## Example Query Sequence

Task: "Spawn enemy scene and attach under root"

1. `suggest_api_for_task(task="spawn enemy scene and add to tree")`
2. `find_method(class_name="PackedScene", method_name="instantiate")`
3. `find_method(class_name="Node", method_name="add_child")`
4. `find_examples(query="instantiate add_child PackedScene", class_name="Node")`
5. Implement with validated call order and ownership notes.
