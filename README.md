# plant-assistant

The assistant answers by calling the plant's tools, and every answer shows the calls behind it; an answer with no call says so.

Article: [llm-that-must-cite-the-plant](https://makemind.dev/en/build/llm-that-must-cite-the-plant)

## What is here

- `assistant/` — Dart MCP server (`mcp_server` from pub.dev). It holds the data and the tools and serves the app's pages as `ui://` resources.
- `plant_server/` — Dart MCP server (`mcp_server` from pub.dev). It holds the data and the tools and serves the app's pages as `ui://` resources.
- `captures/` — screenshots taken from AppPlayer by `verify.py`.
- `verify.py`, `verify.sh` — the check.

## Open it in AppPlayer

Add a server app with command `dart`, arguments `run bin/server.dart`, working directory `assistant/`. The assistant starts `plant_server/` itself and answers through it; the player draws the assistant's page.

## Verify

```bash
bash verify.sh
```

Needs AppPlayer with the debug MCP on (see `tools/README.md`). The script builds what needs building, drives the player through the screens above, asserts the claim at the top of this file, and writes `captures/`.
