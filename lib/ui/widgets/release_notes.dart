import 'package:flutter/material.dart';

/// Renders the GitHub release body shown in the update gate's "What's new".
///
/// The notes arrive as the raw markdown that was published to GitHub, and used
/// to be dumped into a plain [Text], so the user read the literal `##`, `-` and
/// `**` instead of a formatted list. This turns the small subset the release
/// notes actually use into real widgets:
///
///  * `## Heading` / `# Heading` — a bold line above the block it introduces
///  * `- item` / `* item` — a bulleted line with a hanging indent
///  * `**bold**` — bold runs, inline and anywhere in the line
///
/// Deliberately not a markdown package: the notes are written by this repo
/// against a documented format, and the three constructs above are the whole
/// vocabulary. Anything else degrades to the plain text of the line rather
/// than failing — a release body is not worth a render error in front of a
/// user who cannot get past the gate until they update.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes(this.markdown, {super.key});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall;
    final blocks = parseReleaseNotes(markdown);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, block) in blocks.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
            child: switch (block.kind) {
              NoteKind.heading => Text(
                block.text,
                style: base?.copyWith(fontWeight: FontWeight.w600),
              ),
              NoteKind.bullet => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A real bullet with a hanging indent, so a wrapped line
                  // lines up under the text rather than under the dot.
                  Text('•  ', style: base),
                  Expanded(
                    child: Text.rich(_inline(block.text, base), style: base),
                  ),
                ],
              ),
              NoteKind.paragraph => Text.rich(
                _inline(block.text, base),
                style: base,
              ),
            },
          ),
      ],
    );
  }

  /// Splits `**bold**` runs out of [text] into styled spans.
  static TextSpan _inline(String text, TextStyle? base) {
    final bold = base?.copyWith(fontWeight: FontWeight.w600);
    return TextSpan(
      children: [
        for (final (emphasised, run) in parseEmphasis(text))
          TextSpan(text: run, style: emphasised ? bold : null),
      ],
    );
  }
}

/// What a single line of a release body turned into.
enum NoteKind { heading, bullet, paragraph }

/// One rendered line of a release body.
typedef NoteBlock = ({NoteKind kind, String text});

/// Splits a release body into the lines the gate renders.
///
/// Blank lines are dropped rather than preserved as empty blocks: spacing is
/// the renderer's job, and a GitHub body separates every block with one.
List<NoteBlock> parseReleaseNotes(String markdown) {
  final blocks = <NoteBlock>[];
  for (final raw in markdown.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(line);
    if (heading != null) {
      final text = heading.group(1)!.trim();
      if (text.isNotEmpty) {
        // A heading is already emphasised by its own style, so the `**` some
        // bodies wrap it in would otherwise show up as literal asterisks.
        blocks.add((kind: NoteKind.heading, text: _stripEmphasis(text)));
      }
      continue;
    }
    final bullet = RegExp(r'^[-*]\s+(.*)$').firstMatch(line);
    if (bullet != null) {
      final text = bullet.group(1)!.trim();
      if (text.isNotEmpty) blocks.add((kind: NoteKind.bullet, text: text));
      continue;
    }
    blocks.add((kind: NoteKind.paragraph, text: line));
  }
  return blocks;
}

/// Splits [text] into `(emphasised, run)` pairs on `**bold**` markers.
///
/// An unclosed `**` is data, not markup: the trailing run is returned as plain
/// text with the marker intact rather than swallowing the rest of the line.
List<(bool, String)> parseEmphasis(String text) {
  final runs = <(bool, String)>[];
  var index = 0;
  while (index < text.length) {
    final open = text.indexOf('**', index);
    if (open < 0) break;
    final close = text.indexOf('**', open + 2);
    if (close < 0) break;
    if (open > index) runs.add((false, text.substring(index, open)));
    final inner = text.substring(open + 2, close);
    // `****` is not emphasis around nothing -- keep it literal.
    if (inner.isEmpty) {
      runs.add((false, text.substring(open, close + 2)));
    } else {
      runs.add((true, inner));
    }
    index = close + 2;
  }
  if (index < text.length) runs.add((false, text.substring(index)));
  return runs.isEmpty ? [(false, text)] : runs;
}

String _stripEmphasis(String text) =>
    parseEmphasis(text).map((run) => run.$2).join();
