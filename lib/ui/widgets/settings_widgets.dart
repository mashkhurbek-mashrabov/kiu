import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Shared building blocks for the settings surfaces.
///
/// The rule these encode: a row shows a short label and, at most, its current
/// value. Anything longer — why a permission is needed, what Android will do —
/// lives behind [InfoHint] instead of a wrapped subtitle, which is what used
/// to make the sheets scroll for pages.

/// Flat list (Instagram) vs the grouped rounded cards this sheet used before.
///
/// One flag rather than a deletion because the choice is reversible by
/// request: flipping this back to `false` restores the cards without touching
/// the neutral palette, which is a separate decision. Both branches are kept
/// live here so the revert stays a one-line change instead of a rewrite —
/// [SettingsSection] and [SettingsLeading] are the only two places that read
/// it, so the call sites never care either way.
const bool kFlatSettingsRows = false;

/// A grouped block of settings rows with a small caption above it.
///
/// Sections are the only place vertical rhythm is decided, so rows never carry
/// their own outer padding.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.hint,
    this.trailing,
  });

  final String title;
  final IconData? icon;

  /// Explanation covering the section as a whole, shown from an [InfoHint] in
  /// the caption rather than as a paragraph above the rows.
  final String? hint;

  /// Status shown at the right of the caption — e.g. how many reminder times
  /// are active, so the summary is visible without reading every row.
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: colors.onSurfaceVariant),
                  const SizedBox(width: 8),
                ],
                // Expanded, not Flexible + Spacer: those two compete for the
                // same free space, which squeezed a caption like "ЭСЛАТИШ
                // ВАҚТИ" into three mid-word lines once a hint icon shared
                // the row.
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                if (hint != null) InfoHint(message: hint!),
                ?trailing,
              ],
            ),
          ),
          // Material rather than a plain DecoratedBox: rows paint their ink
          // splash on the nearest Material ancestor, so a bare colored box
          // here would silently swallow every tap ripple. That holds for the
          // flat list too — losing the card must not cost the ripple.
          Material(
            color: kFlatSettingsRows
                ? colors.surface
                : colors.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: kFlatSettingsRows
                ? const RoundedRectangleBorder()
                : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  // Hairline between rows only — never above the first or
                  // below the last. In the card that would double the
                  // container edge; in the flat list the section caption and
                  // its gap already mark the boundary.
                  if (i > 0)
                    Divider(
                      height: 1,
                      // Flat rows start their text at the same x as the
                      // caption, so the hairline is indented to the text
                      // rather than to a leading square that no longer exists.
                      indent: kFlatSettingsRows ? 16 : 56,
                      endIndent: kFlatSettingsRows ? 0 : 12,
                      color: colors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable info affordance carrying the long explanation a row used to show
/// inline.
///
/// Tap rather than hover: hover tooltips never fire on a touch screen, so the
/// help would be unreachable on the only platform this app ships to.
class InfoHint extends StatelessWidget {
  const InfoHint({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final key = GlobalKey<TooltipState>();
    return Tooltip(
      key: key,
      message: message,
      triggerMode: TooltipTriggerMode.manual,
      showDuration: const Duration(seconds: 6),
      child: IconButton(
        icon: const Icon(Icons.info_outline_rounded, size: 19),
        color: colors.onSurfaceVariant.withValues(alpha: 0.8),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        tooltip: null,
        onPressed: () => key.currentState?.ensureTooltipVisible(),
      ),
    );
  }
}

/// A row's leading icon.
///
/// Flat: the bare glyph, the way Instagram draws it — the tinted square was
/// the single biggest carrier of green in the sheet. Card: the rounded tinted
/// square, kept behind [kFlatSettingsRows] for the revert.
///
/// Both branches occupy the same 34dp box so the divider indent and every
/// row's optical left edge hold either way.
class SettingsLeading extends StatelessWidget {
  const SettingsLeading(this.icon, {super.key, this.color, this.active = true});

  final IconData icon;

  /// Explicit tint for the rare row that means a color — otherwise the glyph
  /// stays neutral rather than picking up an accent.
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final disabled = colors.onSurface.withValues(alpha: 0.38);
    if (kFlatSettingsRows) {
      return SizedBox(
        width: 34,
        height: 34,
        child: Icon(
          icon,
          size: 24,
          color: active ? (color ?? colors.onSurface) : disabled,
        ),
      );
    }
    final tint = color ?? colors.primary;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: active
            ? tint.withValues(alpha: 0.13)
            : colors.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 19, color: active ? tint : disabled),
    );
  }
}

/// Granted / not-granted pill for a permission row.
///
/// Android permissions can only be changed from the system settings, so the
/// row cannot toggle them — it states the current answer and links out. The
/// badge carries both a color and an icon so the status does not rely on color
/// alone.
class PermissionBadge extends StatelessWidget {
  const PermissionBadge({
    super.key,
    required this.granted,
    required this.grantedLabel,
    required this.deniedLabel,
  });

  final bool granted;
  final String grantedLabel;
  final String deniedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Green for granted, red for not: the one place in settings where colour
    // still carries meaning, kept from the old design because "granted" is
    // worth reading at a glance. Only the badge is tinted — the row's leading
    // icon stays neutral like every other row's.
    //
    // brandGreen, not kiuGreen: the deep brand green fails to read on the
    // near-black dark surface. The icon keeps the distinction for anyone who
    // cannot separate the two hues.
    final foreground = granted ? brandGreen(theme.brightness) : colors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            granted ? Icons.check_circle_rounded : Icons.error_rounded,
            size: 14,
            color: foreground,
          ),
          const SizedBox(width: 4),
          Text(
            granted ? grantedLabel : deniedLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single settings row: icon, short title, optional current value, optional
/// [InfoHint], and a trailing control.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.valueWidget,
    this.hint,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? value;

  /// Rendered in place of [value] when the status needs more than a line of
  /// text — a permission badge, for instance.
  final Widget? valueWidget;
  final String? hint;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListTile(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minVerticalPadding: 12,
      shape: const RoundedRectangleBorder(),
      leading: SettingsLeading(icon, color: iconColor, active: enabled),
      title: Text(
        title,
        // Two lines is enough for the longest translated label; without a cap
        // a long title wraps to a dozen lines and the row becomes a wall.
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: enabled
              ? colors.onSurface
              : colors.onSurface.withValues(alpha: 0.38),
        ),
      ),
      subtitle:
          valueWidget ??
          (value == null
              ? null
              : Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )),
      trailing: _trailing(),
    );
  }

  Widget? _trailing() {
    if (hint == null) return trailing;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InfoHint(message: hint!),
        ?trailing,
      ],
    );
  }
}

/// Switch row. Same anatomy as [SettingsRow] so the two interleave cleanly
/// inside one [SettingsSection].
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.hint,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? hint;
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final titleText = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: enabled
            ? colors.onSurface
            : colors.onSurface.withValues(alpha: 0.38),
      ),
    );
    final content = ListTile(
      contentPadding: const EdgeInsets.only(left: 12),
      minVerticalPadding: 12,
      shape: const RoundedRectangleBorder(),
      leading: SettingsLeading(icon, active: enabled && value),
      title: titleText,
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
      // Hint and switch both live here rather than the hint sitting inside the
      // title: SwitchListTile already reserves the switch's width, so an
      // in-title icon left long labels wrapping mid-word.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hint != null) InfoHint(message: hint!),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
    // Keep the whole row tappable the way SwitchListTile is, minus its layout.
    return InkWell(
      onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
      child: content,
    );
  }
}

/// Sheet header with a back affordance. Every nested sheet uses this so the
/// return path is always in the same place.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    required this.backTooltip,
    this.backKey,
    this.onBack,
  });

  final String title;
  final String backTooltip;
  final Key? backKey;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 16, 4),
    child: Row(
      children: [
        IconButton(
          key: backKey,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: backTooltip,
          onPressed: onBack ?? () => Navigator.pop(context, true),
        ),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
