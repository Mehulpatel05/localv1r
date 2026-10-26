import '../core/constants/areas_and_categories.dart';

class AiCategoryClassifierService {
  static final AiCategoryClassifierService _instance = AiCategoryClassifierService._internal();
  factory AiCategoryClassifierService() => _instance;
  AiCategoryClassifierService._internal();

  static AiCategoryClassifierService get instance => _instance;

  static final Set<String> _alertKeywords = {
    'alert', 'urgent', 'warning', 'emergency', 'cutoff', 'cut', 'shut',
    'shutdown', 'maintenance', 'watercut', 'paani', 'pani', 'bijli', 'light',
    'power', 'electricity', 'supply', 'pipe', 'pipeline', 'leakage', 'leak',
    'bandh', 'band', 'notice', 'caution', 'attention', 'vmc', 'panioff',
    'lightoff', 'powercut', 'drainage', 'gutter', 'cleaning', 'divert',
    'diversion', 'traffic', 'jam', 'danger', 'khatra', 'ચેતવણી', 'પાણી',
    'વીજળી', 'બંધ', 'સમારકામ', 'નોટિસ', 'ધ્યાન',
  };

  static final Set<String> _safetyKeywords = {
    'safety', 'security', 'theft', 'thief', 'chori', 'chor', 'police',
    'guard', 'securityguard', 'stranger', 'suspicious', 'anjaan', 'shakki',
    'dog', 'dogs', 'straydog', 'kutta', 'kutte', 'bite', 'speedbreaker',
    'breaker', 'cctv', 'camera', 'safe', 'unsafe', 'accident', 'fire',
    'aag', 'smoke', 'helmet', 'robbery', 'snatching', 'kid', 'kids',
    'suraksha', 'surakshit', 'સુરક્ષા', 'ચોરી', 'પોલીસ', 'કૂતરા', 'સાવધાન',
  };

  static final Set<String> _eventKeywords = {
    'event', 'events', 'match', 'cricket', 'boxcricket', 'tournament',
    'badminton', 'football', 'sports', 'game', 'garba', 'navratri',
    'diwali', 'holi', 'celebration', 'party', 'gathering', 'meeting',
    'agm', 'puja', 'pooja', 'aarti', 'bhajan', 'satsang', 'festival',
    'festive', 'amphitheatre', 'clubhouse', 'turf', 'invitation', 'invite',
    'bhojan', 'dinner', 'lunch', 'sunday', 'weekend', 'celebrate', 'function',
    'કાર્યક્રમ', 'ગરબા', 'મેચ', 'ટુર્નામેન્ટ', 'પૂજા', 'આરતી', 'સભા',
  };

  static final Set<String> _questionKeywords = {
    '?', 'kahan', 'kidhar', 'kaun', 'kisko', 'kaise', 'kyun', 'kya',
    'kaisa', 'kaisi', 'recommend', 'recommendation', 'suggest', 'suggestion',
    'review', 'advice', 'help', 'chahiye', 'pata', 'maloom', 'batao',
    'batana', 'contact', 'number', 'address', 'where', 'who', 'how',
    'which', 'what', 'why', 'કોણ', 'ક્યાં', 'કેવી', 'કેમ', 'સુ',
    'મદદ', 'નંબર',
  };

  PostCategory classify(String text) {
    final clean = text.toLowerCase().trim();
    if (clean.isEmpty) {
      return PostCategory.general;
    }

    if (clean.contains('?')) {
      final isAlsoAlert = _containsAny(clean, _alertKeywords);
      if (!isAlsoAlert) {
        return PostCategory.question;
      }
    }

    int alertScore = _calculateScore(clean, _alertKeywords);
    int safetyScore = _calculateScore(clean, _safetyKeywords);
    int eventScore = _calculateScore(clean, _eventKeywords);
    int questionScore = _calculateScore(clean, _questionKeywords);

    if (alertScore > 0 && alertScore >= safetyScore && alertScore >= eventScore && alertScore >= questionScore) {
      return PostCategory.alerts;
    }

    if (safetyScore > 0 && safetyScore >= eventScore && safetyScore >= questionScore) {
      return PostCategory.safety;
    }

    if (eventScore > 0 && eventScore >= questionScore) {
      return PostCategory.events;
    }

    if (questionScore > 0) {
      return PostCategory.question;
    }

    return PostCategory.general;
  }

  String detectLanguage(String text) {
    if (text.isEmpty) return 'en';

    int gujaratiChars = 0;
    int devanagariChars = 0;
    int latinChars = 0;

    for (final rune in text.runes) {
      if (rune >= 0x0A80 && rune <= 0x0AFF) {
        gujaratiChars++;
      } else if (rune >= 0x0900 && rune <= 0x097F) {
        devanagariChars++;
      } else if ((rune >= 0x0041 && rune <= 0x005A) || (rune >= 0x0061 && rune <= 0x007A)) {
        latinChars++;
      }
    }

    if (gujaratiChars > 3) {
      return 'gu';
    }
    if (devanagariChars > 3) {
      return 'hi';
    }

    final lower = text.toLowerCase();
    final hinglishMarkers = ['hai', 'hain', 'mein', 'hum', 'aap', 'karo', 'karna', 'kaha', 'raha', 'rahe', 'tha', 'thi', 'chahiye', 'kaale', 'nathi', 'chhe'];
    int markerCount = 0;
    for (final marker in hinglishMarkers) {
      if (lower.contains(marker)) {
        markerCount++;
      }
    }

    if (markerCount >= 2) {
      if (lower.contains('chhe') || lower.contains('nathi') || lower.contains('kaale') || lower.contains('aaje')) {
        return 'gu-Latn';
      }
      return 'hi-Latn';
    }

    return latinChars > 0 ? 'en' : 'hi';
  }

  bool _containsAny(String text, Set<String> keywords) {
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  int _calculateScore(String text, Set<String> keywords) {
    int score = 0;
    final words = text.split(RegExp(r'''[\s,.\-!?"']+'''));
    for (final word in words) {
      if (word.isEmpty) continue;
      if (keywords.contains(word)) {
        score += 2;
      } else {
        for (final kw in keywords) {
          if (kw.length >= 4 && word.startsWith(kw)) {
            score += 1;
            break;
          }
        }
      }
    }
    return score;
  }
}
