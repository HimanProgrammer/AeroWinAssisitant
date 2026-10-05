/// Works out what a message means before acting on it, without any online
/// AI: cleans it up, fixes small typos in key words, then matches it to one
/// of the assistant's commands. Returns the command in the assistant's own
/// words (e.g. "remind me in 10 min to call mom"), or null when the message
/// is just conversation.
String? understand(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return null;

  // A file path (e.g. F:\New folder\drivesync) is handled as-is.
  if (RegExp(r'[A-Za-z]:\s*\\').hasMatch(t)) return raw;

  t = t
      .toLowerCase()
      .replaceAll(RegExp(r"[’‘]"), "'")
      .replaceAll(RegExp(r"[!?,;]+"), ' ')
      .replaceAll(RegExp(r'\.(?=\s|$)'), ' ');
  t = _fixTypos(t);
  t = ' $t ';
  for (final filler in _fillers) {
    t = t.replaceAll(' $filler ', ' ');
  }
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return null;

  bool has(String pattern) => RegExp(pattern).hasMatch(t);
  RegExpMatch? match(String pattern) => RegExp(pattern).firstMatch(t);

  // Reminders, in any word order.
  const unit = r'(seconds?|secs?|minutes?|mins?|m|hours?|hrs?|h)';
  var m = match('^remind me (?:to )?(.+?) in (\\d+) ?$unit\$');
  if (m != null) {
    return 'remind me in ${m.group(2)} ${_unit(m.group(3)!)} to ${m.group(1)}';
  }
  m = match('^in (\\d+) ?$unit remind me (?:to )?(.+)\$');
  if (m != null) {
    return 'remind me in ${m.group(1)} ${_unit(m.group(2)!)} to ${m.group(3)}';
  }
  m = match('^remind me in (\\d+) ?$unit (?:to )?(.+)\$');
  if (m != null) {
    return 'remind me in ${m.group(1)} ${_unit(m.group(2)!)} to ${m.group(3)}';
  }

  // Daily backup time.
  m = match(
    r'(?:daily|every ?day|each day).*?(?:at )?(\d{1,2}(?::\d{2})? ?(?:am|pm)?)$',
  );
  if (m != null && has(r'back ?up|sync|daily')) return 'daily ${m.group(1)}';
  if (has(r'(stop|turn off|cancel|no more) (the )?daily')) return 'daily off';

  // Simple one-word controls.
  if (has(r'^(help|commands|what can you do|what do you do|skills)$')) {
    return 'help';
  }
  if (has(r'^(hide|go away|bye|goodbye|disappear)( for now)?$')) return 'hide';
  if (has(r'^(unmute|talk again|speak again|voice on)$')) return 'unmute';
  if (has(r'^(mute|be quiet|quiet|shut up|silence|voice off)$')) return 'mute';
  if (has(r'\b(update|upgrade|new version|latest version)\b') &&
      !has(r'\bdrive\b')) {
    return 'update';
  }

  // To-do list.
  m =
      match(
        r'^(?:mark |tick |finish(?:ed)? |complete(?:d)? )?(?:task |number |no )?(\d+) (?:is )?(?:done|finished|complete(?:d)?)$',
      ) ??
      match(
        r'^(?:mark|tick|finish(?:ed)?|complete(?:d)?|done)(?: task| number| no)? (\d+)(?: as done| done)?$',
      );
  if (m != null) return 'done ${m.group(1)}';
  if (has(r'^(clear|remove|delete) (the )?(done|finished|completed)')) {
    return 'clear done';
  }
  m =
      match(
        r'^(?:add|put|create)(?: a)?(?: task| to ?do)?(?: to)? (.+?)(?: to (?:my |the )?(?:to ?do|task)s?(?: list)?)?$',
      ) ??
      match(
        r"^(?:i need to|i have to|i must|i should|don't let me forget to|dont let me forget to|remember to|todo|to do) (.+)$",
      );
  if (m != null && !has(r'^add (it|that|this)$')) {
    final task = m.group(1)!.replaceAll(RegExp(r'^(?:to |a task to )'), '');
    return 'add $task';
  }
  if (has(r'\b(to ?do|tasks?|my list|the list)\b') &&
      has(r'\b(show|read|what|tell|list|see|check|my|are)\b')) {
    return 'list';
  }

  // Notes.
  if (has(r'\b(show|read|my|list|see)\b.*\bnotes\b|^notes$')) return 'notes';
  m = match(
    r'^(?:note|make a note|take a note|write down|remember that|note that)(?: that)? (.+)$',
  );
  if (m != null) return 'note ${m.group(1)}';

  // Time and date.
  if (has(r'\btime\b') && !has(r'\bremind\b')) return 'time';
  if (has(r'\b(date|what day|which day|today)\b')) return 'date';

  // Security.
  if (has(r'\b(scan|check|look)\b.*\b(virus(es)?|malware|threats?)\b')) {
    return 'virus scan';
  }
  if (has(
    r'\b(safe|protected|security|antivirus|defender|hacked|malware|virus)\b',
  )) {
    return 'security';
  }

  // Disk and backups.
  if (has(
    r'\b(how much|left|full)\b.*\b(space|storage|disk|drive)\b|^(storage|space|disk)$',
  )) {
    return 'storage';
  }
  if (has(
    r'\b(free (up )?space|clean ?up|maintain|unused|old files|not used|move .*files)\b',
  )) {
    return 'maintain';
  }
  if (has(r'\b(scan|find big files|look for big files|analy[sz]e)\b')) {
    return 'scan';
  }
  if (has(r'\bpending\b|\b(do|finish) (all|everything)\b|^everything$')) {
    return 'pending';
  }
  if (has(r'\b(back ?up|sync|upload)\b')) return 'backup';

  // Opening things.
  m = match(
    r'^(?:open|launch|start|run|go to|show me|bring up)(?: the| my)? (.+?)(?: app| application| website| site| for me)?$',
  );
  if (m != null) return 'open ${m.group(1)}';

  // Status and small talk.
  if (has(
    r"^(status|report|how is everything|how are things|what's up|whats up|any news|update me)$",
  )) {
    return 'status';
  }
  if (has(r'^(hi|hello|hey|yo|good (morning|afternoon|evening))\b')) {
    return 'hi';
  }
  if (has(r'^(thanks|thank you|thx|ty)\b')) return 'thanks';

  return null;
}

String _unit(String u) => u.startsWith('h')
    ? 'hours'
    : u.startsWith('s')
    ? 'seconds'
    : 'minutes';

const _fillers = [
  'please',
  'pls',
  'plz',
  'kindly',
  'can you',
  'could you',
  'would you',
  'will you',
  'can u',
  'could u',
  'i want you to',
  'i would like you to',
  "i'd like you to",
  'hey assistant',
  'assistant',
  'buddy',
  'for me',
  'just',
  'quickly',
  'right now',
];

const _keywords = [
  'backup',
  'remind',
  'minutes',
  'seconds',
  'hours',
  'open',
  'note',
  'notes',
  'list',
  'todo',
  'tasks',
  'task',
  'done',
  'security',
  'virus',
  'malware',
  'scan',
  'storage',
  'space',
  'maintain',
  'pending',
  'update',
  'unmute',
  'status',
  'help',
  'daily',
  'time',
  'date',
  'today',
  'protected',
  'please',
  'remember',
  'everything',
  'finished',
  'complete',
  'upload',
  'drivesync',
];

/// Fixes one-letter slips in key words ("bakup", "remnd", "staus").
String _fixTypos(String t) => t
    .split(' ')
    .map((w) {
      if (w.length < 4 || _keywords.contains(w)) return w;
      for (final k in _keywords) {
        if ((k.length - w.length).abs() <= 1 &&
            _distance(w, k) <= (k.length >= 7 ? 2 : 1)) {
          return k;
        }
      }
      return w;
    })
    .join(' ');

int _distance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = [i, ...List<int>.filled(b.length, 0)];
    for (var j = 1; j <= b.length; j++) {
      cur[j] = [
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      ].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}
