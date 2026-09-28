import 'package:mcp_llm/mcp_llm.dart';

/// A stand-in for the model, so this sample can be run and verified by anyone
/// without an API key.
///
/// **This is not the interesting part of the article.** It exists because a
/// sample whose output changes every run, and which costs money and a secret to
/// execute, cannot be checked by a reader. What is worth reading is everything
/// *around* it: how the plant's MCP tools reach a model, what a tool call looks
/// like coming back, and how the result is fed in for the final answer. That
/// wiring is identical whether the object below is this class or Claude.
///
/// Swapping in the real thing is two lines — see `bin/ask.dart`.
///
/// What it does: reads the question, picks a tool the way a model would, and
/// once the tool result comes back, writes the answer from the numbers in it.
/// It never invents a reading, and it never invents a checklist step, because
/// the point of the exercise is that neither should the real model.
class BenchProvider implements LlmProvider {
  BenchProvider({this.label = 'bench'});

  final String label;

  /// Every decision this provider made, for the write-up.
  final List<String> decisions = <String>[];

  @override
  Future<void> initialize(LlmConfiguration config) async {}

  @override
  Future<void> close() async {}

  @override
  Future<List<double>> getEmbeddings(String text) async =>
      List<double>.filled(8, 0);

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    final r = await complete(request);
    yield LlmResponseChunk(textChunk: r.text, isDone: true);
  }

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    final prompt = request.prompt;

    // The follow-up turn: the tool has run and its output is in the prompt the
    // orchestrator built. Answer from that text and nothing else.
    final toolResult = _extractToolResult(prompt);
    if (toolResult != null) {
      decisions.add('answer from tool result (${toolResult.length} chars)');
      return LlmResponse(text: _answerFrom(toolResult));
    }

    // The first turn: choose a tool, the way a model choosing among the tool
    // descriptions it was handed would.
    final q = prompt.toLowerCase();
    final machineId = _machineIdIn(q);

    if (machineId != null && (q.contains('check') || q.contains('safe') ||
        q.contains('procedure') || q.contains('checklist'))) {
      final type = _typeOf(machineId);
      decisions.add('chose checklist.get(machineType: $type)');
      return LlmResponse(
        text: '',
        toolCalls: [
          LlmToolCall(name: 'checklist.get', arguments: {'machineType': type}),
        ],
      );
    }

    if (machineId != null) {
      decisions.add('chose equipment.read(id: $machineId)');
      return LlmResponse(
        text: '',
        toolCalls: [
          LlmToolCall(name: 'equipment.read', arguments: {'id': machineId}),
        ],
      );
    }

    if (q.contains('line a') || q.contains('line b') || q.contains('machines') ||
        q.contains('what is on') || q.contains('list')) {
      final line = q.contains('line b') ? 'B' : 'A';
      decisions.add('chose equipment.list(line: $line)');
      return LlmResponse(
        text: '',
        toolCalls: [
          LlmToolCall(name: 'equipment.list', arguments: {'line': line}),
        ],
      );
    }

    // No tool fits. Saying so is a valid answer; guessing is not.
    decisions.add('no tool matched — declined to guess');
    return LlmResponse(
      text: 'I can look up machines, their current readings, and the plant '
          'checklist for a machine type. Ask me about one of those.',
    );
  }

  // ---- the small amount of reading this stand-in does --------------------

  static final _idPattern = RegExp(r'(press-01|conv-03|weld-07)');

  String? _machineIdIn(String q) =>
      _idPattern.firstMatch(q)?.group(1)?.toUpperCase();

  String _typeOf(String id) {
    if (id.startsWith('PRESS')) return 'press';
    if (id.startsWith('CONV')) return 'conveyor';
    return 'welder';
  }

  /// The orchestrator hands the tool's output back inside the follow-up prompt.
  /// Find the JSON object in it; if there is none, this is not a follow-up.
  String? _extractToolResult(String prompt) {
    final start = prompt.indexOf('{"');
    if (start < 0) return null;
    final end = prompt.lastIndexOf('}');
    if (end <= start) return null;
    return prompt.substring(start, end + 1);
  }

  /// Turn the tool output into a sentence, using only what is in it.
  String _answerFrom(String json) {
    if (json.contains('"steps"')) {
      final steps = RegExp(r'"([^"]{20,})"')
          .allMatches(json)
          .map((m) => m.group(1)!)
          .where((s) => !s.contains('machineType'))
          .toList();
      final numbered = steps
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value}')
          .join('\n');
      return 'Plant checklist, in the order it is written:\n$numbered\n'
          'These steps are the plant engineer\'s. Do not reorder or skip them.';
    }

    if (json.contains('"machines"')) {
      final names = RegExp(r'"id":"([A-Z0-9-]+)"')
          .allMatches(json)
          .map((m) => m.group(1)!)
          .toList();
      return 'That line has ${names.length} machines: ${names.join(", ")}.';
    }

    final id = RegExp(r'"id":"([A-Z0-9-]+)"').firstMatch(json)?.group(1);
    final hours = RegExp(r'"runHours":(\d+)').firstMatch(json)?.group(1);
    final interval =
        RegExp(r'"serviceEveryHours":(\d+)').firstMatch(json)?.group(1);
    final vib = RegExp(r'"vibrationMm":([\d.]+)').firstMatch(json)?.group(1);
    final vibLimit =
        RegExp(r'"vibrationLimitMm":([\d.]+)').firstMatch(json)?.group(1);
    final overdue = json.contains('"serviceOverdue":true');
    final vibOver = json.contains('"vibrationOverLimit":true');

    if (id == null) return 'The tool returned something I cannot read: $json';

    final flags = <String>[];
    if (overdue) flags.add('service is overdue ($hours h against a $interval h interval)');
    if (vibOver) flags.add('vibration is above limit ($vib mm against $vibLimit mm)');

    if (flags.isEmpty) {
      return '$id: $hours run hours of a $interval h interval, vibration $vib mm '
          '(limit $vibLimit mm). Nothing is over its limit right now.';
    }
    return '$id needs attention — ${flags.join(" and ")}. '
        'Ask me for the checklist before working on it.';
  }

  @override
  bool hasToolCallMetadata(Map<String, dynamic> metadata) =>
      metadata.containsKey('tool_call');

  @override
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) => null;

  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) =>
      metadata;

  @override
  bool get supportsPromptCaching => false;
}

/// Registering a provider is how mcp_llm is told what to talk to. The real
/// providers are registered exactly this way, which is why the swap is small.
class BenchProviderFactory implements LlmProviderFactory {
  BenchProviderFactory(this.provider);

  final BenchProvider provider;

  @override
  String get name => 'bench';

  @override
  Set<LlmCapability> get capabilities => {
        LlmCapability.completion,
        LlmCapability.toolUse,
      };

  @override
  LlmProvider createProvider(LlmConfiguration config) => provider;
}
