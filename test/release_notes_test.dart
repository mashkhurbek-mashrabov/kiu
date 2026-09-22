import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/ui/widgets/release_notes.dart';

/// The shape a published GitHub release body actually has, marker already
/// stripped by `UpdateService`.
const _body = '''
## Changes

- **Activation keys now work on one device only.** Copy the ID and send it.
- **Existing keys have stopped working.**

## Fixes

- **Google Meet lesson links open again.** Tapping "Darsga kirish" now opens
  the meeting.
''';

void main() {
  group('parseReleaseNotes', () {
    test('reads headings and bullets out of a release body', () {
      final blocks = parseReleaseNotes(_body);
      expect(blocks.first, (kind: NoteKind.heading, text: 'Changes'));
      expect(blocks.map((b) => b.kind).toList(), [
        NoteKind.heading,
        NoteKind.bullet,
        NoteKind.bullet,
        NoteKind.heading,
        NoteKind.bullet,
        // The wrapped continuation line of the last bullet.
        NoteKind.paragraph,
      ]);
    });

    test('drops blank lines and keeps every heading level', () {
      final blocks = parseReleaseNotes('# One\n\n\n###### Six\n');
      expect(blocks, [
        (kind: NoteKind.heading, text: 'One'),
        (kind: NoteKind.heading, text: 'Six'),
      ]);
    });

    test('takes either bullet marker', () {
      expect(parseReleaseNotes('- dash\n* star'), [
        (kind: NoteKind.bullet, text: 'dash'),
        (kind: NoteKind.bullet, text: 'star'),
      ]);
    });

    test('strips the emphasis a heading wraps itself in', () {
      expect(parseReleaseNotes('## **Fixes**'), [
        (kind: NoteKind.heading, text: 'Fixes'),
      ]);
    });

    test('keeps a bare hash or lone text as a paragraph', () {
      expect(parseReleaseNotes('#nospace\nplain'), [
        (kind: NoteKind.paragraph, text: '#nospace'),
        (kind: NoteKind.paragraph, text: 'plain'),
      ]);
    });

    test('survives an empty body', () {
      expect(parseReleaseNotes(''), isEmpty);
      expect(parseReleaseNotes('\n\n'), isEmpty);
    });
  });

  group('parseEmphasis', () {
    test('splits bold runs out of a line', () {
      expect(parseEmphasis('**Bold.** Then plain.'), [
        (true, 'Bold.'),
        (false, ' Then plain.'),
      ]);
    });

    test('handles bold in the middle and several runs', () {
      expect(parseEmphasis('a **b** c **d**'), [
        (false, 'a '),
        (true, 'b'),
        (false, ' c '),
        (true, 'd'),
      ]);
    });

    test('leaves an unclosed marker as literal text', () {
      expect(parseEmphasis('a **b'), [(false, 'a **b')]);
    });

    test('leaves an empty marker pair literal', () {
      expect(parseEmphasis('a ****b'), [
        (false, 'a '),
        (false, '****'),
        (false, 'b'),
      ]);
    });

    test('returns plain text untouched', () {
      expect(parseEmphasis('nothing special'), [(false, 'nothing special')]);
    });
  });

  testWidgets('renders notes with no literal markdown markers on screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ReleaseNotes(_body))),
    );

    // The regression this fixes: the user used to read the raw `##`, `-` and
    // `**` characters. Every Text the tree renders must be clean of them.
    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? text.textSpan!.toPlainText())
        .join('\n');
    expect(rendered, isNot(contains('**')));
    expect(rendered, isNot(contains('##')));
    expect(rendered, contains('Changes'));
    expect(rendered, contains('Activation keys now work on one device only.'));

    // And the bold run is really bold, not merely stripped.
    final bullet = tester.widget<Text>(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.textSpan?.toPlainText().startsWith('Activation keys') ?? false),
      ),
    );
    final spans = (bullet.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.style?.fontWeight, FontWeight.w600);
  });
}
