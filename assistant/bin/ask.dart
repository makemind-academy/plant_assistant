import 'dart:convert';
import 'dart:io';

import 'package:mcp_client/mcp_client.dart';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:plant_assistant/bench_provider.dart';
import 'package:plant_assistant/prompt.dart';

/// ask — a technician asks in words; the answer is built from the plant's own
/// tools.
///
///   plant_server (mcp_server)  ──MCP──▶  mcp_client  ──▶  LlmClient  ──▶  model
///        equipment.list                                       │
///        equipment.read       ◀───── tool call ────────────────┘
///        checklist.get        ─────  result  ─────▶  answer written from it
///
/// Run:  dart run bin/ask.dart "how is PRESS-01 doing?"
///
/// The model in the middle is a stand-in (see lib/bench_provider.dart) so the
/// sample runs without an API key. Everything on either side of it is the real
/// thing.
Future<void> main(List<String> args) async {
  final questions = args.isNotEmpty
      ? args
      : const [
          'what machines are on line A?',
          'how is CONV-03 doing?',
          'what is the checklist before I work on CONV-03?',
          'how is PRESS-01 doing?',
          'what is the weather like?',
        ];

  // 1. Connect to the plant. This is an ordinary MCP client — the assistant has
  //    no privileged channel, it uses the same surface anything else would.
  final connected = await McpClient.createAndConnect(
    config: McpClient.simpleConfig(name: 'Plant Assistant', version: '1.0.0'),
    transportConfig: const TransportConfig.stdio(
      command: 'dart',
      arguments: ['run', 'bin/server.dart'],
      workingDirectory: '../plant_server',
    ),
  );
  final mcpClient = connected.get();

  final tools = await mcpClient.listTools();
  stdout.writeln('# tools offered by the plant: '
      '${tools.map((t) => t.name).join(", ")}');

  // 2. Register a provider and build the client that joins the two.
  //
  //    For a real model this is where the swap happens, and it is the whole
  //    swap:
  //
  //      llm.registerProvider('claude', ClaudeProviderFactory());
  //      final client = await llm.createClient(
  //        providerName: 'claude',
  //        config: LlmConfiguration(apiKey: Platform.environment['ANTHROPIC_API_KEY'],
  //                                 model: 'claude-sonnet-5'),
  //        mcpClient: mcpClient,
  //        systemPrompt: systemPrompt,
  //      );
  //
  //    Nothing below this point changes.
  final bench = BenchProvider();
  final llm = McpLlm()..registerProvider('bench', BenchProviderFactory(bench));

  final client = await llm.createClient(
    providerName: 'bench',
    config: LlmConfiguration(model: 'bench-1'),
    mcpClient: mcpClient,
    systemPrompt: assistantSystemPrompt,
  );

  // 3. Ask.
  for (final q in questions) {
    stdout.writeln('\n> $q');
    final response = await client.chat(q, enableTools: true);
    stdout.writeln(response.text.trim());
  }

  // 4. What the plant was actually asked. An assistant's answer is only worth
  //    what the record behind it is worth.
  final audit = await mcpClient.callTool('audit.log', const {});
  final first = audit.content.first;
  if (first is TextContent) {
    final calls = (jsonDecode(first.text) as Map<String, dynamic>)['calls'] as List;
    stdout.writeln('\n# tool calls the plant actually received (${calls.length}):');
    for (final c in calls) {
      stdout.writeln('#   $c');
    }
  }
  stdout.writeln('\n# provider decisions (${bench.decisions.length}):');
  for (final d in bench.decisions) {
    stdout.writeln('#   $d');
  }

  await client.close();
  mcpClient.dispose();
  exit(0);
}
