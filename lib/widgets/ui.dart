import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';

// Small shared Material 3 building blocks used by every screen so spacing,
// typography and colours stay consistent.

enum Tone { info, success, warning, error, neutral }

Color toneFg(Tone t) {
  switch (t) {
    case Tone.success: return const Color(0xFF0F6D33);
    case Tone.warning: return const Color(0xFF8A4B00);
    case Tone.error: return const Color(0xFFB42318);
    case Tone.neutral: return AppColors.ink2;
    case Tone.info: return AppColors.teal2;
  }
}

Color toneBg(Tone t) {
  switch (t) {
    case Tone.success: return AppColors.greenSoft;
    case Tone.warning: return AppColors.yellowSoft;
    case Tone.error: return AppColors.redSoft;
    case Tone.neutral: return const Color(0xFFEFF3F4);
    case Tone.info: return AppColors.tealSoft;
  }
}

/// Floating SnackBar (sits above the bottom navigation bar).
void showSnack(BuildContext context, String msg, {Tone tone = Tone.neutral}) {
  if (msg.trim().isEmpty) return;
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  final Color? bg = tone == Tone.success
      ? const Color(0xFF166534)
      : tone == Tone.error
          ? const Color(0xFFB42318)
          : tone == Tone.warning
              ? const Color(0xFF92400E)
              : null;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: bg));
}

/// Section heading used above groups of cards.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionTitle(this.text,
      {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 8)});
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.teal2, fontWeight: FontWeight.w700, letterSpacing: 0.1)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Rounded pill showing a booking / payout status (same wording as the web badge).
class StatusBadge extends StatelessWidget {
  final String status;
  final String paymentStatus;
  final String? label;
  const StatusBadge(this.status, {super.key, this.paymentStatus = '', this.label});
  @override
  Widget build(BuildContext context) {
    final s = StatusStyle.of(status, paymentStatus: paymentStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label ?? s.label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: s.fg)),
    );
  }
}

/// Soft coloured info box with an icon.
class Notice extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Tone tone;
  final Widget? action;
  final EdgeInsetsGeometry margin;
  const Notice(this.text,
      {super.key, this.icon, this.tone = Tone.info, this.action, this.margin = EdgeInsets.zero});
  @override
  Widget build(BuildContext context) {
    final fg = toneFg(tone);
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: toneBg(tone), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon ?? _defaultIcon, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13.5, height: 1.35, color: fg, fontWeight: FontWeight.w500)),
          ),
        ]),
        if (action != null) ...[const SizedBox(height: 8), action!],
      ]),
    );
  }

  IconData get _defaultIcon {
    switch (tone) {
      case Tone.success: return Icons.check_circle_outline_rounded;
      case Tone.warning: return Icons.schedule_rounded;
      case Tone.error: return Icons.error_outline_rounded;
      default: return Icons.info_outline_rounded;
    }
  }
}

/// Centered icon + text for empty lists.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: const BoxDecoration(color: AppColors.tealSoft, shape: BoxShape.circle),
          child: Icon(icon, size: 30, color: AppColors.teal),
        ),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: t.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: AppColors.muted)),
        ],
        if (action != null) ...[const SizedBox(height: 14), action!],
      ]),
    );
  }
}

/// Rounded tinted square holding an icon (leading of list rows).
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconTile(this.icon, {super.key, this.color = AppColors.teal, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
            color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(size * 0.3)),
        child: Icon(icon, color: color, size: size * 0.55),
      );
}

/// Value + label tile (dashboard / earnings stats).
class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onTap;
  const StatTile(
      {super.key, required this.value, required this.label, this.icon, this.color = AppColors.teal, this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (icon != null) ...[Icon(icon, size: 20, color: color), const SizedBox(height: 8)],
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
            ),
            const SizedBox(height: 2),
            Row(children: [
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
              ),
              if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.muted),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Label / value row.
class KeyValueRow extends StatelessWidget {
  final String k;
  final String v;
  final bool bold;
  final Color? valueColor;
  const KeyValueRow(this.k, this.v, {super.key, this.bold = false, this.valueColor});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 14, color: AppColors.muted))),
          Text(v,
              style: TextStyle(
                  fontSize: bold ? 16 : 14,
                  color: valueColor ?? AppColors.ink,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ]),
      );
}

/// Icon + text detail line (address, slot, notes…).
class DetailLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  final int? maxLines;
  const DetailLine(this.icon, this.text, {super.key, this.color, this.maxLines});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color ?? AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                maxLines: maxLines,
                overflow: maxLines == null ? null : TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.3, color: AppColors.ink2)),
          ),
        ]),
      );
}

/// Booking summary chips (tasks + the customer's job-question answers).
class SummaryChips extends StatelessWidget {
  final List<String> items;
  final WrapAlignment alignment;
  const SummaryChips(this.items, {super.key, this.alignment = WrapAlignment.start});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: alignment,
      children: items
          .map((s) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: AppColors.tealSoft, borderRadius: BorderRadius.circular(99)),
                child: Text(s,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.teal2)),
              ))
          .toList(),
    );
  }
}

/// Circle avatar with photo or initial.
class Avatar extends StatelessWidget {
  final String name;
  final String photo;
  final double radius;
  final Color bg;
  final Color fg;
  const Avatar(
      {super.key, required this.name, this.photo = '', this.radius = 24, this.bg = AppColors.tealSoft, this.fg = AppColors.teal2});
  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
        child: photo.isEmpty
            ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'P',
                style: TextStyle(fontSize: radius * 0.8, color: fg, fontWeight: FontWeight.w700))
            : null,
      );
}

/// 4-box OTP input. The controller lives in the caller's State, so whatever
/// the provider typed survives every poll / rebuild (same as the web keeping
/// typed digits across a refresh).
class OtpInput extends StatefulWidget {
  final TextEditingController controller;
  final int length;
  final String? errorText;
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  const OtpInput(
      {super.key, required this.controller, this.length = 4, this.errorText, this.onCompleted, this.enabled = true});
  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(OtpInput old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final hasErr = (widget.errorText ?? '').isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Stack(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.length, (i) {
            final filled = i < text.length;
            final current = _focus.hasFocus && i == text.length.clamp(0, widget.length - 1);
            return Container(
              width: 58,
              height: 62,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: filled ? AppColors.tealSoft : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: hasErr
                        ? AppColors.red
                        : current
                            ? AppColors.teal
                            : const Color(0xFFC5D3D7),
                    width: current || hasErr ? 2 : 1.2),
              ),
              child: Text(filled ? text[i] : '',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.ink)),
            );
          }),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              maxLength: widget.length,
              showCursor: false,
              enableInteractiveSelection: false,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) {
                if (v.length == widget.length) widget.onCompleted?.call(v);
              },
              decoration: const InputDecoration(
                  counterText: '', border: InputBorder.none, filled: false),
            ),
          ),
        ),
      ]),
      if (hasErr)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(widget.errorText!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
    ]);
  }
}

/// Horizontal progress of a booking:
/// Quote → Confirmed → Started → Completed → Paid.
class JobStepper extends StatelessWidget {
  final String status;
  final bool paid;
  const JobStepper({super.key, required this.status, this.paid = false});

  static const _labels = ['Quoted', 'Confirmed', 'Started', 'Done', 'Paid'];

  int get _index {
    switch (status) {
      case 'price_quoted':
      case 'negotiating':
      case 'negotiation_final':
        return 0;
      case 'confirmed':
        return 1;
      case 'active':
        return 2;
      case 'completed':
        return paid ? 5 : 3;
      default:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = _index;
    final items = <Widget>[];
    for (var i = 0; i < _labels.length; i++) {
      final done = i < cur || (i == cur && i == 4);
      final active = i == cur && !done;
      final color = done ? AppColors.teal : active ? AppColors.brand : const Color(0xFFC5D3D7);
      items.add(Expanded(
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Container(
                    height: 3,
                    color: i == 0
                        ? Colors.transparent
                        : (i <= cur ? AppColors.teal : const Color(0xFFDDE7EA)))),
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: done ? AppColors.teal : active ? AppColors.brand : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: done
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : active
                      ? const Icon(Icons.circle, size: 8, color: Colors.white)
                      : null,
            ),
            Expanded(
                child: Container(
                    height: 3,
                    color: i == _labels.length - 1
                        ? Colors.transparent
                        : (i < cur ? AppColors.teal : const Color(0xFFDDE7EA)))),
          ]),
          const SizedBox(height: 6),
          Text(_labels[i],
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: done || active ? AppColors.ink : AppColors.muted)),
        ]),
      ));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: items);
  }
}

/// Full-width primary action with an optional busy spinner.
class BigButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final Color? color;
  final bool outlined;
  const BigButton(this.label,
      {super.key, this.icon, this.onPressed, this.busy = false, this.color, this.outlined = false});
  @override
  Widget build(BuildContext context) {
    final Widget child = busy
        ? SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: outlined ? (color ?? AppColors.teal) : Colors.white))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ]);
    final onTap = busy ? null : onPressed;
    if (outlined) {
      return OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          foregroundColor: color ?? AppColors.teal,
          side: BorderSide(color: (color ?? AppColors.teal).withOpacity(0.6)),
        ),
        child: child,
      );
    }
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        backgroundColor: color,
      ),
      child: child,
    );
  }
}
