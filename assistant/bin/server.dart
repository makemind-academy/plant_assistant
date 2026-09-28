import 'dart:async';
import 'dart:convert';

import 'package:mcp_client/mcp_client.dart' as mcp_client;
import 'package:mcp_llm/mcp_llm.dart'
    hide CallToolResult, ReadResourceResult;
import 'package:mcp_server/mcp_server.dart';
import 'package:plant_assistant/bench_provider.dart';
import 'package:plant_assistant/screens.dart';

/// assistant server — a client on one side, a server on the other.
///
///   plant_server ◀──MCP── THIS ──MCP──▶ technician's tablet
///                (client)      (server)
///
/// It consumes the plant's tools like any other client, and it serves a screen
/// like any other server. The model sits in the middle and is the only piece
/// that is a stand-in here.
///
/// Worth noticing: the tablet never talks to the plant. It asks the assistant a
/// question and gets back an answer *plus the tool calls that produced it*. The
/// technician can see what was actually asked before trusting the sentence.
void main(List<String> args) async {
  final plant = await mcp_client.McpClient.createAndConnect(
    config: mcp_client.McpClient.simpleConfig(
      name: 'Plant Assistant',
      version: '1.0.0',
    ),
    transportConfig: const mcp_client.TransportConfig.stdio(
      command: 'dart',
      arguments: ['run', 'bin/server.dart'],
      workingDirectory: '../plant_server',
    ),
  );
  final plantClient = plant.get();

  final bench = BenchProvider();
  final llm = McpLlm()..registerProvider('bench', BenchProviderFactory(bench));
  final llmClient = await llm.createClient(
    providerName: 'bench',
    config: LlmConfiguration(model: 'bench-1'),
    mcpClient: plantClient,
    systemPrompt: assistantSystemPrompt,
  );

  const config = McpServerConfig(
    name: 'Plant Assistant',
    version: '1.0.0',
    capabilities: ServerCapabilities(
      tools: ToolsCapability(listChanged: true),
      resources: ResourcesCapability(listChanged: true),
    ),
  );
  final server = McpServer.createServer(config);
  AssistantServer(server, llmClient, plantClient, bench).register();

  final transport = McpServer.createStdioTransport().get();
  server.connect(transport);

  await Completer<void>().future;
}

/// "1 call", "2 calls". A screen that says "1 call(s)" is a screen nobody
/// proofread.
String _plural(int n, String one) => "$n $one" + (n == 1 ? "" : "s");

class AssistantServer {
  AssistantServer(this.server, this.llm, this.plant, this.bench);

  final Server server;
  final LlmClient llm;
  final mcp_client.Client plant;
  final BenchProvider bench;

  String _question = '-';
  String _answer = 'Ask about a machine, its readings, or the checklist.';
  List<String> _toolCalls = const [];
  String _notice = '';

  void register() {
    // The app and the screen its route names — the same resource convention
    // every server app here follows.
    const documents = <String, (String, String, Map<String, dynamic>)>{
      'ui://app': ('Plant assistant', 'Routes and the plant\'s theme',
          applicationDefinition),
      'ui://app/info': ('App Info', 'Lightweight metadata (spec 11.6)',
          appInfoDefinition),
      'ui://pages/assistant': ('Plant Assistant',
          'Answer plus the tool calls behind it', assistantDefinition),
    };
    documents.forEach((uri, spec) {
      final (name, description, document) = spec;
      server.addResource(
        uri: uri,
        name: name,
        description: description,
        mimeType: 'application/json',
        handler: (requestedUri, params) async => ReadResourceResult(
          contents: [
            ResourceContentInfo(
              uri: requestedUri,
              mimeType: 'application/json',
              text: jsonEncode(document),
            ),
          ],
        ),
      );
    });

    server.addTool(
      name: 'assistant.ask',
      description: 'Ask a question about the plant',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'question': {'type': 'string'},
        },
        'required': ['question'],
      },
      handler: (args) async {
        final question = (args['question'] as String?)?.trim() ?? '';
        if (question.isEmpty) {
          _notice = 'Empty question';
          return _state();
        }
        _question = question;

        // Mark where the plant's audit log stands, so we can attribute exactly
        // the calls this question caused — not everything since boot.
        final before = await _auditCalls();
        final response = await llm.chat(question, enableTools: true);
        final after = await _auditCalls();

        _answer = response.text.trim();
        _toolCalls = after.sublist(before.length);
        _notice = _toolCalls.isEmpty
            ? 'No tool was called. Treat this as the assistant talking about '
              'itself, not about the plant.'
            : '';
        return _state();
      },
    );

    server.addTool(
      name: 'assistant.state',
      description: 'Current question, answer and the tool calls behind it',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async => _state(),
    );
  }

  Future<List<String>> _auditCalls() async {
    final r = await plant.callTool('audit.log', const {});
    final first = r.content.first;
    if (first is! mcp_client.TextContent) return const [];
    final calls = (jsonDecode(first.text) as Map<String, dynamic>)['calls'] as List;
    // audit.log is itself a tool call, but it is ours, not the assistant's —
    // counting it would inflate every answer's evidence by one.
    return calls.cast<String>().where((c) => !c.startsWith('audit.log')).toList();
  }

  CallToolResult _state() => CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'question': _question,
              'answer': _answer,
              'toolCalls': _toolCalls,
              'toolCallCount': _toolCalls.length,
              'grounded': _toolCalls.isNotEmpty,
              // Said in words, not as a colour: an answer with no call behind
              // it is not wrong, it is unsupported, and the difference is the
              // whole point of showing the calls at all.
              'groundedLabel': _toolCalls.isEmpty
                  ? 'no tool call behind this answer — it stands on the model alone'
                  : 'grounded in ${_plural(_toolCalls.length, "call")} to the plant',
              'plantRule': 'Every answer carries the calls that produced it · '
                  'the plant is the source, the model is the phrasing',
              'notice': _notice,
            }),
          ),
        ],
      );
}
