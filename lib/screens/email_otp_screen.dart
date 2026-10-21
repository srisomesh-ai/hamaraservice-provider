import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/provider_api_service.dart';
import '../utils/theme.dart';

/// Registration: enter the 6-digit code e-mailed by otp.php (before the
/// application is submitted).
///
/// The code has already been sent when this screen opens. Pops with the
/// `otp_token` on success, or `null` for "Change email" / back.
class EmailOtpScreen extends StatefulWidget {
  final String email;
  final String purpose;
  final String verifyLabel;

  /// Seconds before "Resend code" is enabled (server: `resend_in`).
  final int resendAfter;

  /// Overridable for tests; default: otp.php verify / send.
  final Future<String> Function(String code)? verify;
  final Future<int> Function()? resend;

  const EmailOtpScreen({
    super.key,
    required this.email,
    this.purpose = 'provider_register',
    this.verifyLabel = 'Verify & Submit Application',
    this.resendAfter = 60,
    this.verify,
    this.resend,
  });

  @override
  State<EmailOtpScreen> createState() => _EmailOtpScreenState();
}

class _EmailOtpScreenState extends State<EmailOtpScreen> {
  static const _len = 6;
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  late int _wait = widget.resendAfter;
  bool _busy = false;
  bool _resending = false;
  String _error = '';
  String _info = '';

  @override
  void initState() {
    super.initState();
    _startCountdown(widget.resendAfter);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _wait = seconds < 0 ? 0 : seconds);
    if (_wait == 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != _len) {
      setState(() => _error = 'Enter the 6-digit code from the email');
      _focus.requestFocus();
      return;
    }
    if (_busy) return;
    setState(() { _busy = true; _error = ''; _info = ''; });
    try {
      final verify = widget.verify ??
          (c) => ProviderApiService.verifyEmailOtp(widget.email, c, purpose: widget.purpose);
      final token = await verify(code);
      if (mounted) Navigator.pop(context, token);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = e.message; });
      _code.clear();
      _focus.requestFocus();
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = 'Verification failed. Please try again.'; });
    }
  }

  Future<void> _resend() async {
    if (_wait > 0 || _resending) return;
    setState(() { _resending = true; _error = ''; _info = ''; });
    try {
      final resend = widget.resend ??
          () => ProviderApiService.sendEmailOtp(widget.email, purpose: widget.purpose);
      final wait = await resend();
      if (!mounted) return;
      _code.clear();
      setState(() { _resending = false; _info = 'A new code has been sent'; });
      _startCountdown(wait);
      _focus.requestFocus();
    } on ApiException catch (e) {
      if (mounted) setState(() { _resending = false; _error = e.message; });
    } catch (_) {
      if (mounted) setState(() { _resending = false; _error = 'Could not send email, please try again'; });
    }
  }

  String get _waitText {
    final m = _wait ~/ 60, s = _wait % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Verify email')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Center(
              child: Container(
                width: 72, height: 72,
                decoration: const BoxDecoration(color: AppColors.tealSoft, shape: BoxShape.circle),
                child: const Icon(Icons.mark_email_read_outlined, size: 36, color: AppColors.teal),
              ),
            ),
            const SizedBox(height: 20),
            Text('Check your email',
                textAlign: TextAlign.center,
                style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Enter the 6-digit code we sent to\n'),
                TextSpan(
                    text: widget.email,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              ]),
              textAlign: TextAlign.center,
              style: t.bodyLarge?.copyWith(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 28),
            _CodeBoxes(
              controller: _code,
              focusNode: _focus,
              length: _len,
              hasError: _error.isNotEmpty,
              onChanged: (v) {
                if (_error.isNotEmpty || _info.isNotEmpty) setState(() { _error = ''; _info = ''; });
                if (v.length == _len) _verify();
              },
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Banner(text: _error, error: true),
            ] else if (_info.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Banner(text: _info, error: false),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _verify,
              child: _busy
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(widget.verifyLabel),
            ),
            const SizedBox(height: 12),
            // Wrap: on narrow phones "Change email" moves under "Resend"
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: (_wait > 0 || _resending || _busy) ? null : _resend,
                  icon: _resending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded, size: 20),
                  label: Text(_wait > 0 ? 'Resend in $_waitText' : 'Resend code'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Change email'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('The code is valid for 10 minutes. Not in your inbox? Check your spam folder.',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// Six digit boxes backed by one invisible numeric field (keeps paste and
/// SMS/e-mail code autofill working).
class _CodeBoxes extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool hasError;
  final ValueChanged<String> onChanged;
  const _CodeBoxes({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.hasError,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      height: 60,
      child: Stack(children: [
        AnimatedBuilder(
          animation: Listenable.merge([controller, focusNode]),
          builder: (context, _) {
            final text = controller.text;
            return Row(
              children: List.generate(length, (i) {
                final filled = i < text.length;
                final active = focusNode.hasFocus &&
                    (i == text.length || (text.length == length && i == length - 1));
                final color = hasError
                    ? AppColors.red
                    : active
                        ? AppColors.teal
                        : filled
                            ? AppColors.teal2
                            : AppColors.line;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i == length - 1 ? 0 : 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: filled ? AppColors.tealSoft : AppColors.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color, width: active || hasError ? 2 : 1.4),
                    ),
                    child: Text(filled ? text[i] : '',
                        style: t.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ),
                );
              }),
            );
          },
        ),
        Positioned.fill(
          child: TextField(
            key: const ValueKey('otp-field'),
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(length),
            ],
            showCursor: false,
            enableInteractiveSelection: false,
            style: const TextStyle(color: Colors.transparent, fontSize: 1),
            // invisible: the boxes above show the digits
            decoration: const InputDecoration(
              isCollapsed: true,
              filled: false,
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
            ),
            onChanged: onChanged,
          ),
        ),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final bool error;
  const _Banner({required this.text, required this.error});

  @override
  Widget build(BuildContext context) {
    final fg = error ? AppColors.red : AppColors.green;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: error ? AppColors.redSoft : AppColors.greenSoft,
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: fg, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg))),
      ]),
    );
  }
}
