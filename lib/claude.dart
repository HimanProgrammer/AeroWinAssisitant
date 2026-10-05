import 'dart:convert';
import 'dart:io';

/// Talks to Claude through the Anthropic Messages API (plain HTTPS: there is
/// no official Anthropic SDK for Dart). Claude only answers and plans; it
/// never runs anything on this PC.
class Claude {
  Claude(this.apiKey);
  final String apiKey;

  static const model = 'claude-opus-5-5';
  static const _system =
      "You are Aero, a friendly floating personal assistant on the user's "
      'Windows PC. Reply in 1-3 short sentences, plainly, because replies are '
      'shown in a small speech bubble and read aloud. You cannot run commands '
      "or touch files yourself. When it helps, tell the user which Aero "
      'command to type, e.g. "add <task> 15 min", "remind me in 10 min to '
      '<x>", "backup", "maintain", "list".';

  /// Sends a chat [history] (oldest first, (fromUser, text)) and returns
  /// Claude's reply, or a short error message.
  Future<String> chat(List<(bool, String)> history) async {
    final messages = <Map<String, Object>>[];
    for (final (mine, text) in history) {
      final role = mine ? 'user' : 'assistant';
      if (messages.isNotEmpty && messages.last['role'] == role) {
        messages.last['content'] = '${messages.last['content']}\n$text';
      } else {
        messages.add({'role': role, 'content': text});
      }
    }
    while (messages.isNotEmpty && messages.first['role'] != 'user') {
      messages.removeAt(0);
    }
    if (messages.isEmpty || messages.last['role'] != 'user') {
      return 'Ask me something first.';
    }
    final res = await _send({
      'model': model,
      'max_tokens': 2000,
      'system': _system,
      'messages': messages,
      'output_config': {'effort': 'low'},
    });
    return res.text ?? res.error!;
  }

  /// Estimates minutes for each task and suggests an order.
  Future<({Map<int, int> minutes, List<int> order, String summary})?> plan(
    List<String> tasks,
  ) async {
    final numbered = [
      for (var i = 0; i < tasks.length; i++) '${i + 1}. ${tasks[i]}',
    ].join('\n');
    final res = await _send({
      'model': model,
      'max_tokens': 4000,
      'system': _system,
      'messages': [
        {
          'role': 'user',
          'content':
              'Here is my to-do list:\n$numbered\n\nEstimate realistic '
              'minutes for each task and suggest the best order to do them '
              'today. Keep the summary to two short sentences.',
        },
      ],
      'output_config': {
        'effort': 'medium',
        'format': {
          'type': 'json_schema',
          'schema': {
            'type': 'object',
            'additionalProperties': false,
            'required': ['tasks', 'order', 'summary'],
            'properties': {
              'tasks': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'additionalProperties': false,
                  'required': ['number', 'minutes'],
                  'properties': {
                    'number': {'type': 'integer'},
                    'minutes': {'type': 'integer'},
                  },
                },
              },
              'order': {
                'type': 'array',
                'items': {'type': 'integer'},
              },
              'summary': {'type': 'string'},
            },
          },
        },
      },
    });
    if (res.text == null) return null;
    try {
      final m = jsonDecode(res.text!) as Map<String, dynamic>;
      return (
        minutes: {
          for (final t in (m['tasks'] as List).cast<Map<String, dynamic>>())
            (t['number'] as num).toInt(): (t['minutes'] as num).toInt(),
        },
        order: [for (final n in m['order'] as List) (n as num).toInt()],
        summary: '${m['summary']}',
      );
    } catch (_) {
      return null;
    }
  }

  Future<({String? text, String? error})> _send(
    Map<String, Object> body,
  ) async {
    // Server-side fallback: if a request is declined, the API retries it on
    // another model in the same call.
    body['fallbacks'] = 'default';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(
        Uri.parse('https://api.anthropic.com/v1/messages'),
      );
      req.headers
        ..set('x-api-key', apiKey)
        ..set('anthropic-version', '2023-06-01')
        ..set('anthropic-beta', 'server-side-fallback-2026-07-01')
        ..contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(minutes: 3));
      final raw = await utf8.decoder.bind(res).join();
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        final msg =
            (m['error'] as Map?)?['message'] ?? 'HTTP ${res.statusCode}';
        if (res.statusCode == 401) {
          return (
            text: null,
            error: 'Claude rejected the API key. Set it again with: claude key <your key>',
          );
        }
        return (text: null, error: 'Claude error: $msg');
      }
      if (m['stop_reason'] == 'refusal') {
        return (text: null, error: "Claude declined that request.");
      }
      final text = (m['content'] as List)
          .cast<Map<String, dynamic>>()
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'])
          .join()
          .trim();
      return text.isEmpty
          ? (text: null, error: 'Claude sent an empty reply.')
          : (text: text, error: null);
    } catch (e) {
      return (text: null, error: "Couldn't reach Claude: $e");
    } finally {
      client.close();
    }
  }
}
