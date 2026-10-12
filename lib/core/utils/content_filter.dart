class ContentFilter {
  // Prohibited terms for instant blocking based on local safety guidelines (India-specific)
  static final List<String> _blockedKeywords = [
    'doxx', 'leak', 'aadhaar', 'pan card', 'threaten', 'mardu', 'gali',
    'scam', 'fraud', 'cheat', 'hack', 'bribe'
  ];

  /// Scans post text for potential violations under IT Rules 2021 (doxxing, harassment)
  /// and returns an error message if flagged, or null if allowed.
  static final List<String> _profaneKeywords = [
    'chutiya', 'chutiye', 'chutya', 'bhosdike', 'bhosadi', 'bhosada', 'bhosadike',
    'madarchod', 'behenchod', 'bhenchod', 'gaand', 'gand', 'lauda',
    'loda', 'lavda', 'lodu', 'harami', 'kameena', 'kamina', 'saala', 'sala',
    'kutta', 'kutte', 'randi', 'randa', 'chut', 'jhant', 'jhaant', 'fuck',
    'fucking', 'fucked', 'bitch', 'asshole', 'bastard', 'shit', 'cunt', 'dick',
    'pussy', 'slut', 'whore'
  ];

  static String? validateContent(String text) {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return 'Post content cannot be empty.';
    }

    if (cleanText.length < 5) {
      return 'Post content is too short. Please add more details.';
    }

    final lower = cleanText.toLowerCase();
    for (final word in _profaneKeywords) {
      final wordRegex = RegExp(r'\b' + RegExp.escape(word) + r'\b', caseSensitive: false);
      if (wordRegex.hasMatch(lower)) {
        return 'Please keep it respectful.';
      }
    }

    final phoneRegex = RegExp(r'\b[6-9]\d{9}\b');
    if (phoneRegex.hasMatch(cleanText)) {
      return 'Action Blocked: To protect privacy and prevent doxxing (DPDP Act 2023), sharing phone numbers is strictly prohibited.';
    }

    final upiRegex = RegExp(r'\b[a-zA-Z0-9.\-_]{2,64}@(okhdfcbank|okaxis|oksbi|okicici|paytm|ybl|ibl|axl|upi|apl|barodampay)\b', caseSensitive: false);
    if (upiRegex.hasMatch(cleanText)) {
      return 'Action Blocked: Sharing UPI handles or payment details is prohibited to prevent financial fraud/scams.';
    }

    for (final word in _blockedKeywords) {
      final wordRegex = RegExp(r'\b' + RegExp.escape(word) + r'\b', caseSensitive: false);
      if (wordRegex.hasMatch(lower)) {
        return 'Action Blocked: Your post contains language or keywords flagged for safety (prohibited content/harassment policy).';
      }
    }

    return null;
  }
}
