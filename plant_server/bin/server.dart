import 'dart:async';
import 'dart:convert';

import 'package:mcp_server/mcp_server.dart';

/// plant_server — the tools a maintenance assistant is allowed to use.
///
/// A plant already knows things. It knows which machines exist, how many hours
/// they have run, what their last vibration reading was, and what the safety
/// checklist for each one says. What it has never had is a way for the person
/// standing in front of the machine to ask.
///
/// This server does not answer questions. It exposes the facts as tools and
/// stops there — deciding which tool answers which question is the assistant's
/// job, and deciding what is safe is the plant engineer's, encoded in the
/// checklists below.
void main(List<String> args) async {
  const config = McpServerConfig(
    name: 'Plant Server',
    version: '1.0.0',
    capabilities: ServerCapabilities(
      tools: ToolsCapability(listChanged: true),
      resources: ResourcesCapability(listChanged: true),
    ),
  );

  final server = McpServer.createServer(config);
  PlantServer(server).register();

  final transport = McpServer.createStdioTransport().get();
  server.connect(transport);

  await Completer<void>().future;
}

/// The plant, as it would come out of a maintenance database.
const _machines = <String, Map<String, dynamic>>{
  'PRESS-01': {
    'name': 'Hydraulic press 1',
    'line': 'A',
    'runHours': 4820,
    'serviceEveryHours': 5000,
    'vibrationMm': 2.1,
    'vibrationLimitMm': 4.5,
    'oilTempC': 61,
    'oilTempLimitC': 75,
  },
  'CONV-03': {
    'name': 'Conveyor 3',
    'line': 'A',
    'runHours': 9310,
    'serviceEveryHours': 8000,
    'vibrationMm': 5.2,
    'vibrationLimitMm': 4.5,
    'oilTempC': 44,
    'oilTempLimitC': 70,
  },
  'WELD-07': {
    'name': 'Spot welder 7',
    'line': 'B',
    'runHours': 1200,
    'serviceEveryHours': 3000,
    'vibrationMm': 0.8,
    'vibrationLimitMm': 3.0,
    'oilTempC': 38,
    'oilTempLimitC': 65,
  },
};

/// The checklist is the plant engineer's, not the assistant's. An assistant
/// that invented its own safety steps would be worse than no assistant.
const _checklists = <String, List<String>>{
  'press': [
    'Isolate hydraulic supply and confirm zero pressure at the gauge',
    'Apply lockout tag to the main disconnect',
    'Check ram guide clearance with feeler gauge',
    'Inspect hose runs for chafing at the moving joint',
  ],
  'conveyor': [
    'Lock out drive motor and confirm the belt is free',
    'Check bearing housing temperature by hand before opening',
    'Inspect belt tracking and edge wear over one full rotation',
    'Verify emergency pull-cord continuity along both sides',
  ],
  'welder': [
    'Isolate secondary and confirm no residual charge',
    'Inspect electrode tips for mushrooming',
    'Check coolant flow and return temperature',
  ],
};

class PlantServer {
  PlantServer(this.server);

  final Server server;

  /// Everything the tools did, in order. The article prints this: an assistant
  /// that claims to have checked a machine is worth less than the record of it
  /// having actually asked.
  static final List<String> auditLog = <String>[];

  void register() {
    server.addTool(
      name: 'equipment.list',
      description:
          'List the machines in the plant, optionally filtered by production line. '
          'Returns machine ids and names.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'line': {'type': 'string', 'description': 'Production line, e.g. "A"'},
        },
      },
      handler: (args) async {
        final line = args['line'] as String?;
        final rows = _machines.entries
            .where((e) => line == null || e.value['line'] == line)
            .map((e) => {'id': e.key, 'name': e.value['name'], 'line': e.value['line']})
            .toList();
        auditLog.add('equipment.list(line: $line) -> ${rows.length} machines');
        return _json({'machines': rows});
      },
    );

    server.addTool(
      name: 'equipment.read',
      description:
          'Read the current condition of one machine: run hours, service interval, '
          'vibration and oil temperature, each with the limit it is measured against.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'id': {'type': 'string', 'description': 'Machine id, e.g. "PRESS-01"'},
        },
        'required': ['id'],
      },
      handler: (args) async {
        final id = (args['id'] as String?)?.toUpperCase();
        final m = _machines[id];
        if (m == null) {
          auditLog.add('equipment.read(id: $id) -> NOT FOUND');
          return _json({'error': 'no such machine', 'id': id});
        }
        // The server states the facts and how they compare to their limits. It
        // does not say whether the machine is "fine" — that word belongs to a
        // person with a checklist.
        final overdue = (m['runHours'] as int) > (m['serviceEveryHours'] as int);
        final vibrationOver =
            (m['vibrationMm'] as num) > (m['vibrationLimitMm'] as num);
        auditLog.add('equipment.read(id: $id) -> overdue=$overdue '
            'vibrationOver=$vibrationOver');
        return _json({
          'id': id,
          ...m,
          'serviceOverdue': overdue,
          'vibrationOverLimit': vibrationOver,
        });
      },
    );

    server.addTool(
      name: 'checklist.get',
      description:
          'Get the plant safety checklist for a machine type (press, conveyor, welder). '
          'These steps are set by the plant engineer and must not be paraphrased.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'machineType': {'type': 'string'},
        },
        'required': ['machineType'],
      },
      handler: (args) async {
        final type = (args['machineType'] as String?)?.toLowerCase();
        final steps = _checklists[type];
        auditLog.add('checklist.get(machineType: $type) -> ${steps?.length ?? 0} steps');
        if (steps == null) {
          return _json({'error': 'no checklist for this type', 'machineType': type});
        }
        return _json({'machineType': type, 'steps': steps});
      },
    );

    server.addTool(
      name: 'audit.log',
      description: 'Return the record of tool calls made against this plant.',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async => _json({'calls': auditLog}),
    );
  }

  CallToolResult _json(Map<String, dynamic> payload) =>
      CallToolResult(content: [TextContent(text: jsonEncode(payload))]);
}
