class ContentFilter {
  // Prohibited terms for instant blocking based on local safety guidelines (India-specific)
  static final List<String> _blockedKeywords = [
    'doxx', 'leak', 'aadhaar', 'pan card', 'threaten', 'mardu', 'maru', 'gali',
    'scam', 'fraud', 'cheat', 'hack', 'bribe', 'rupees', 'rs'
  ];

  /// Scans post text for potential violations under IT Rules 2021 (doxxing, harassment)
  /// and returns an error message if flagged, or null if allowed.
  static String? validateContent(String text) {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return 'Post content cannot be empty.';
    }

    if (cleanText.length < 5) {
      return 'Post content is too short. Please add more details.';
    }

    // Check for 10-digit Indian phone number pattern to prevent doxxing
    final phoneRegex = RegExp(r'\b[6-9]\d{9}\b');
    if (phoneRegex.hasMatch(cleanText)) {
      return 'Action Blocked: To protect privacy and prevent doxxing (DPDP Act 2023), sharing phone numbers is strictly prohibited.';
    }

    // Check for UPI ID pattern (e.g. name@upi or name@paytm) to prevent scams/impersonation
    final upiRegex = RegExp(r'[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}');
    if (upiRegex.hasMatch(cleanText)) {
      return 'Action Blocked: Sharing UPI handles or payment details is prohibited to prevent financial fraud/scams.';
    }

    // Check for blocklisted words
    final lower = cleanText.toLowerCase();
    for (final word in _blockedKeywords) {
      if (lower.contains(word)) {
        return 'Action Blocked: Your post contains language or keywords flagged for safety (prohibited content/harassment policy).';
      }
    }

    return null;
  }
}
