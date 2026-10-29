import 'package:flutter/material.dart';
import '../config/theme.dart';

enum NoteTone { neutral, warning, danger }

/// A quiet callout with a coloured edge, for guidance that should not shout.
class InfoNote extends StatelessWidget {
  const InfoNote(this.text, {super.key, this.tone = NoteTone.neutral});

  final String text;
  final NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final (edge, fill, ink) = switch (tone) {
      NoteTone.warning => (const Color(0xFFD9A441), MokgosiColors.warningSoft, MokgosiColors.warning),
      NoteTone.danger => (MokgosiColors.danger, MokgosiColors.dangerSoft, MokgosiColors.danger),
      NoteTone.neutral => (MokgosiColors.accent, MokgosiColors.accentSoft, MokgosiColors.ink),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: edge, width: 3)),
      ),
      child: Text(text, style: TextStyle(color: ink, fontSize: 14, height: 1.4)),
    );
  }
}

/// Small muted heading above a group of settings or actions.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(color: MokgosiColors.inkMuted, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// "Hide" in the app bar: jumps straight back to the calculator screen.
class HideAction extends StatelessWidget {
  const HideAction({super.key, required this.onPressed, this.label = 'Hide'});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton(onPressed: onPressed, child: Text(label)),
    );
  }
}

/// +26771234567 -> +267 71 234 567; other numbers are returned unchanged.
String formatPhone(String? e164) {
  final match = RegExp(r'^\+267(\d{2})(\d{3})(\d{3})$').firstMatch(e164 ?? '');
  return match == null ? (e164 ?? '') : '+267 ${match[1]} ${match[2]} ${match[3]}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Tue 28 Oct, 19:42" in local time; the raw value if it cannot be parsed.
String formatWhen(String? iso) {
  final parsed = DateTime.tryParse(iso ?? '');
  if (parsed == null) return iso ?? '';
  final t = parsed.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}, ${two(t.hour)}:${two(t.minute)}';
}
