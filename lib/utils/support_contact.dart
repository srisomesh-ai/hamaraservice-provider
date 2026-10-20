import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/provider_api_service.dart';
import 'parse.dart';

// Single place for HamaraService support contact details.
// The WhatsApp number and email come from site.php?action=config (set on the
// server, so they change without an app release); kSupportEmail is only the
// fallback while that has not loaded.

const String kSupportEmail = 'info@hamaraservice.com';

class SupportConfig {
  final String whatsapp; // digits incl. country code, e.g. 919876543210 ('' = none)
  final String email;
  const SupportConfig(this.whatsapp, this.email);
  bool get hasWhatsapp => whatsapp.isNotEmpty;
}

SupportConfig? _cached;
Future<SupportConfig>? _inflight;

/// Last loaded config (or the email-only fallback). Never null.
SupportConfig get supportConfigNow =>
    _cached ?? const SupportConfig('', kSupportEmail);

/// Loads (once per app run) site.php?action=config. Never throws.
Future<SupportConfig> loadSupportConfig({bool force = false}) {
  if (!force && _cached != null) return Future.value(_cached);
  return _inflight ??= () async {
    try {
      final res = await ProviderApiService.getSiteConfig();
      if (res.ok) {
        final m = res.map ?? {};
        _cached = SupportConfig(
          str(m['support_whatsapp']).replaceAll(RegExp(r'\D'), ''),
          str(m['support_email'], kSupportEmail),
        );
      }
    } catch (_) {}
    _inflight = null;
    return supportConfigNow;
  }();
}

/// Builds a mailto: link to support. Query values are percent-encoded
/// (spaces as %20) because many mail apps do not decode '+'.
Uri supportMailto({required String subject, required String body, String? email}) {
  String enc(String s) => Uri.encodeComponent(s);
  final to = email ?? supportConfigNow.email;
  return Uri.parse('mailto:$to?subject=${enc(subject)}&body=${enc(body)}');
}

/// Standard support message, always including the provider id.
String supportMessage({String providerId = '', String context = ''}) =>
    'Hi HamaraService support, I am a provider'
    '${providerId.isNotEmpty ? ' (ID: $providerId)' : ''}.'
    '${context.isNotEmpty ? ' $context' : ''} I need help with: ';

/// Opens WhatsApp chat with support (https://wa.me/<number>?text=…), or the
/// mail app when no WhatsApp number is configured. Returns false (and shows a
/// snackbar) when nothing could be opened.
Future<bool> openSupport(BuildContext context,
    {String providerId = '', String extra = '', String? message}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final cfg = await loadSupportConfig();
  final text = message ?? supportMessage(providerId: providerId, context: extra);
  final Uri uri = cfg.hasWhatsapp
      ? Uri.parse('https://wa.me/${cfg.whatsapp}?text=${Uri.encodeComponent(text)}')
      : supportMailto(
          subject: 'Provider support${providerId.isNotEmpty ? ' ($providerId)' : ''}',
          body: text,
          email: cfg.email);
  bool ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok) {
    messenger?.showSnackBar(SnackBar(
      content: Text(cfg.hasWhatsapp
          ? 'Could not open WhatsApp. Please write to ${cfg.email}'
          : 'No email app found. Please write to ${cfg.email}'),
      backgroundColor: const Color(0xFFE53E3E),
    ));
  }
  return ok;
}
