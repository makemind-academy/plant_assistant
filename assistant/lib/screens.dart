/// The technician's screen.
///
/// It shows the answer and, underneath it, the tool calls that produced the
/// answer. That second part is not decoration. An assistant that says "the
/// conveyor is overdue" is worth exactly as much as the record of it having
/// asked the plant — and on a factory floor the person reading it is about to
/// put their hands inside a machine.
///
/// It is an `application` with one route rather than a loose page: the colours
/// belong to the plant and are declared once, and a second screen (a
/// supervisor's, a tablet at the line) inherits them instead of restating them.
library;

export 'prompt.dart';

const _ink = '{{theme.color.onSurface}}';
const _muted = '{{theme.color.onSurfaceVariant}}';
const _accent = '{{theme.color.primary}}';
const _hair = '{{theme.color.outline}}';
const _surface = '{{theme.color.surface}}';
const _canvas = '{{theme.color.surfaceContainerHighest}}';
const _warn = '{{theme.color.warning}}';
const _mono = 'JetBrainsMono';

/// A works floor: light, high contrast, one warm accent for the thing that
/// needs a person.
const Map<String, dynamic> _plantTheme = {
  'mode': 'light',
  'color': {
    'primary': '#c2410c',
    'onPrimary': '#ffffff',
    'primaryContainer': '#f7e3d7',
    'onPrimaryContainer': '#431604',
    'surface': '#ffffff',
    'onSurface': '#101418',
    'surfaceContainerHighest': '#f3f4f6',
    'onSurfaceVariant': '#7c8894',
    'outline': '#e4e7ea',
    'outlineVariant': '#eef0f2',
    'error': '#b3261e',
    'onError': '#ffffff',
    'warning': '#a4620a',
    'onWarning': '#ffffff',
    'inverseSurface': '#101418',
    'inverseOnSurface': '#f3f4f6',
  },
  'spacing': {
    'xxs': 2, 'xs': 4, 'sm': 8, 'md': 16, 'lg': 24, 'xl': 32, '2xl': 48,
  },
  'shape': {
    'none': 0, 'extraSmall': 4, 'small': 8, 'medium': 12, 'large': 16,
    'extraLarge': 28, 'full': 999,
  },
  'fonts': {
    'JetBrainsMono': {'source': 'asset', 'family': 'JetBrainsMono'},
  },
};

const Map<String, dynamic> _initialState = {
  'question': '-',
  'answer': 'Ask about a machine, its readings, or the checklist.',
  'toolCalls': <dynamic>[],
  'toolCallCount': 0,
  'grounded': false,
  'groundedLabel': 'no tool call behind this answer',
  'plantRule': '',
  'notice': '',
};

const Map<String, dynamic> applicationDefinition = {
  'type': 'application',
  'version': '1.3',
  'id': 'plant.assistant',
  'title': 'Plant assistant',
  'description': 'Answers about the line, with the calls that produced them.',
  'theme': _plantTheme,
  'initialRoute': '/assistant',
  'routes': {'/assistant': 'ui://pages/assistant'},
  'state': {'initial': _initialState},
};

/// Spec 11.6 — what a launcher shows before loading anything.
const Map<String, dynamic> appInfoDefinition = {
  'id': 'plant.assistant',
  'title': 'Plant assistant',
  'description': 'Answers about the line, with the calls that produced them.',
  'version': '1.0.0',
  'publisher': {'name': 'Plant maintenance'},
};

const Map<String, dynamic> assistantDefinition = {
  'type': 'page',
  'metadata': {'title': 'Plant Assistant'},
  'state': {'initial': _initialState},
  'content': {
    'type': 'container',
    'decoration': {'color': _canvas},
    'child': {
      'type': 'linear',
      'direction': 'vertical',
      'crossAxisAlignment': 'stretch',
      'children': [
        // Who is asking, and about which line.
        {
          'type': 'container',
          'padding': {'left': 24, 'right': 24, 'top': 20, 'bottom': 16},
          'decoration': {
            'color': _surface,
            'border': {'bottom': true, 'color': _hair, 'width': 1},
          },
          'child': {
            'type': 'linear',
            'direction': 'horizontal',
            'crossAxisAlignment': 'center',
            'children': [
              {
                'type': 'linear',
                'direction': 'vertical',
                'gap': 4,
                'children': [
                  {
                    'type': 'text',
                    'content': 'LINE 2 · MAINTENANCE',
                    'style': {
                      'fontSize': 12,
                      'color': _muted,
                      'letterSpacing': 2.0
                    },
                  },
                  {
                    'type': 'text',
                    'content': '{{question}}',
                    'style': {
                      'fontSize': 20,
                      'fontWeight': 'bold',
                      'color': _ink
                    },
                  },
                ],
              },
              {'type': 'spacer'},
              {
                'type': 'linear',
                'direction': 'vertical',
                'gap': 4,
                'crossAxisAlignment': 'end',
                'children': [
                  {
                    'type': 'text',
                    'content': 'TOOL CALLS',
                    'style': {
                      'fontSize': 11,
                      'color': _muted,
                      'letterSpacing': 1.6
                    },
                  },
                  {
                    'type': 'text',
                    'content': '{{toolCallCount}}',
                    'style': {
                      'fontSize': 26,
                      'fontFamily': _mono,
                      'color': _ink
                    },
                  },
                ],
              },
            ],
          },
        },
        // Controls the reader presses in the player; the harness used to call these tools itself.
        {'type': 'container', 'padding': {'left': 22, 'right': 22, 'top': 10, 'bottom': 4}, 'child': {'type': 'linear', 'direction': 'horizontal', 'crossAxisAlignment': 'center', 'children': [{'type': 'button', 'label': 'How is CONV-03 doing?', 'variant': 'outlined', 'onTap': {'type': 'tool', 'tool': 'assistant.ask', 'params': {'question': 'how is CONV-03 doing?'}}}, {'type': 'box', 'width': 10}, {'type': 'button', 'label': 'Checklist before CONV-03', 'variant': 'outlined', 'onTap': {'type': 'tool', 'tool': 'assistant.ask', 'params': {'question': 'what is the checklist before I work on CONV-03?'}}}, {'type': 'box', 'width': 10}, {'type': 'button', 'label': 'What is the weather like?', 'variant': 'outlined', 'onTap': {'type': 'tool', 'tool': 'assistant.ask', 'params': {'question': 'what is the weather like?'}}}]}},
        // The answer, and immediately under it the standing of that answer.
        {
          'type': 'container',
          'padding': {'left': 24, 'right': 24, 'top': 18, 'bottom': 8},
          'child': {
            'type': 'container',
            'padding': {'all': 20},
            'decoration': {
              'color': _surface,
              'borderRadius': 14,
              'border': {'color': _hair, 'width': 1},
            },
            'child': {
              'type': 'linear',
              'direction': 'vertical',
              'gap': 12,
              'crossAxisAlignment': 'stretch',
              'children': [
                {
                  'type': 'text',
                  'content': '{{answer}}',
                  'style': {'fontSize': 18, 'color': _ink},
                },
                {'type': 'divider', 'color': _hair},
                {
                  'type': 'text',
                  'content': '{{groundedLabel}}',
                  'style': {'fontSize': 13, 'color': _warn},
                },
              ],
            },
          },
        },
        // What it asked the plant, verbatim. This is the part a technician is
        // entitled to before putting their hands inside a machine.
        {
          'type': 'expanded',
          'child': {
            'type': 'container',
            'padding': {'left': 24, 'right': 24, 'top': 8, 'bottom': 8},
            'child': {
              'type': 'container',
              'padding': {'all': 18},
              'decoration': {
                'color': _surface,
                'borderRadius': 14,
                'border': {'color': _hair, 'width': 1},
              },
              'child': {
                'type': 'linear',
                'direction': 'vertical',
                'gap': 10,
                'crossAxisAlignment': 'stretch',
                'children': [
                  {
                    'type': 'text',
                    'content': 'WHAT IT ASKED THE PLANT',
                    'style': {
                      'fontSize': 11,
                      'color': _muted,
                      'letterSpacing': 1.6
                    },
                  },
                  {
                    'type': 'expanded',
                    'child': {
                      'type': 'list',
                      'items': '{{toolCalls}}',
                      'shrinkWrap': true,
                      'itemSpacing': 8,
                      'emptyMessage':
                          'It asked the plant nothing — this answer stands on '
                              'the model alone',
                      'itemTemplate': {
                        'type': 'text',
                        'content': '{{item}}',
                        'style': {
                          'fontSize': 14,
                          'fontFamily': _mono,
                          'color': _ink
                        },
                      },
                    },
                  },
                ],
              },
            },
          },
        },
        {
          'type': 'container',
          'padding': {'left': 24, 'right': 24, 'top': 4, 'bottom': 18},
          'child': {
            'type': 'linear',
            'direction': 'horizontal',
            'crossAxisAlignment': 'center',
            'children': [
              {
                'type': 'expanded',
                'child': {
                  'type': 'text',
                  'content': '{{plantRule}}',
                  'style': {'fontSize': 13, 'color': _muted},
                },
              },
              {
                'type': 'text',
                'content': '{{notice}}',
                'style': {'fontSize': 13, 'color': _accent},
              },
            ],
          },
        },
      ],
    },
  },
};
