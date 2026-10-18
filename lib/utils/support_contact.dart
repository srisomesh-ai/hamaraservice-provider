// Single place for HamaraService support contact details.

const String kSupportEmail = 'info@hamaraservice.com';

// TODO(hamaraservice): set the real support phone / WhatsApp number
// (10-digit Indian mobile, no +91). While empty, the Call and WhatsApp
// buttons are hidden and only email support is offered.
const String kSupportPhone = '';

bool get hasSupportPhone => kSupportPhone.isNotEmpty;

/// Builds a mailto: link to support. Query values are percent-encoded
/// (spaces as %20) because many mail apps do not decode '+'.
Uri supportMailto({required String subject, required String body}) {
  String enc(String s) => Uri.encodeComponent(s);
  return Uri.parse('mailto:$kSupportEmail?subject=${enc(subject)}&body=${enc(body)}');
}
