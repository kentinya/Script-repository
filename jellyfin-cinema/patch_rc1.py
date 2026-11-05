from pathlib import Path
p = Path('lib/main.dart')
s = p.read_text(encoding='utf-8')
fixes = [
 ("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart' hide RepeatMode;"),
 ('separatorBuilder: (_, _) => const SizedBox(width: 18)', 'separatorBuilder: (context, index) => const SizedBox(width: 18)'),
 ('errorBuilder: (_, _, _) =>', 'errorBuilder: (context, exception, stackTrace) =>'),
 ('      tooltip: name,\n      onTap:', '      onTap:'),
 ('''if (mounted) setState(() {
      library = null; resumeItems = []; nextUpItems = [];
      tab = 0; search.clear(); password.clear(); error = null;
    });''', '''if (mounted) {
      setState(() {
        library = null; resumeItems = []; nextUpItems = [];
        tab = 0; search.clear(); password.clear(); error = null;
      });
    }'''),
 ('''if (mounted) setState(() {
        resumeItems = results[0]; nextUpItems = results[1]; dashboardWarning = null;
      });''', '''if (mounted) {
        setState(() {
          resumeItems = results[0]; nextUpItems = results[1]; dashboardWarning = null;
        });
      }'''),
 ('if (reset) searching = true;\n      else searchMoreBusy = true;', 'if (reset) { searching = true; }\n      else { searchMoreBusy = true; }'),
 ('if (reset) searchResults = page.items;\n        else {', 'if (reset) { searchResults = page.items; }\n        else {'),
 ('''if (mounted && version == _searchVersion) setState(() {
        searching = false;
        searchMoreBusy = false;
      });''', '''if (mounted && version == _searchVersion) {
        setState(() {
          searching = false;
          searchMoreBusy = false;
        });
      }''')
]
for old, new in fixes:
    if old not in s:
        raise RuntimeError('Expected source fragment missing: ' + repr(old[:90]))
    s = s.replace(old, new)
p.write_text(s, encoding='utf-8')
p = Path('lib/session_store.dart')
s = p.read_text(encoding='utf-8')
old = 'server.isEmpty || userId.isEmpty || token.isEmpty) return null;'
if old not in s:
    raise RuntimeError('Expected session store source fragment missing')
p.write_text(s.replace(old, 'server.isEmpty || userId.isEmpty || token.isEmpty) { return null; }'), encoding='utf-8')
Path('test/widget_test.dart').write_text("""import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MaterialApp smoke test', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Cinema'))));
    expect(find.text('Cinema'), findsOneWidget);
  });
}
""", encoding='utf-8')
# This mock payload contains Chinese subtitle metadata. http.Response defaults to
# latin1 unless a UTF-8 content-type is supplied, so the mock must match
# Jellyfin's JSON response encoding. Otherwise the mock throws synchronously
# and the API correctly classifies that exception as a network failure.
p = Path('test/source_selection_test.dart')
s = p.read_text(encoding='utf-8')
old = "      ]}), 200);"
new = "      ]}), 200, headers: {'content-type': 'application/json; charset=utf-8'});"
if s.count(old) != 1:
    raise RuntimeError('Expected one playback-info mock response, found ' + str(s.count(old)))
p.write_text(s.replace(old, new), encoding='utf-8')
print('Applied RC1 compilation and UTF-8 mock-response corrections.')
