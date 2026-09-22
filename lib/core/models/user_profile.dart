import 'package:flutter/foundation.dart' show immutable;

/// Immutable model representing a user's public profile data.
@immutable
class UserProfile {
  final String handle;
  final String? phone;
  final String? email;
  final int joinedYear;

  const UserProfile({
    required this.handle,
    this.phone,
    this.email,
    required this.joinedYear,
  });

  factory UserProfile.fromMap(
    Map<String, dynamic> data, {
    String fallbackHandle = '',
  }) {
    final handle = (data['handle'] as String?)?.trim() ?? fallbackHandle;
    final rawPhone = (data['phone'] ?? data['phoneNumber'] ?? data['mobile'] as String?)?.toString().trim();
    final rawEmail = (data['email'] as String?)?.trim();
    final createdAt = data['createdAt'];

    int year = DateTime.now().year;
    if (createdAt != null) {
      try {
        // Supports Firestore Timestamp (.toDate()) or raw DateTime.
        final dt = createdAt.runtimeType.toString().contains('Timestamp')
            ? (createdAt as dynamic).toDate() as DateTime
            : createdAt as DateTime;
        year = dt.year;
      } catch (_) {}
    }

    return UserProfile(
      handle: handle,
      phone: (rawPhone == null || rawPhone.isEmpty) ? null : rawPhone,
      email: (rawEmail == null || rawEmail.isEmpty) ? null : rawEmail,
      joinedYear: year,
    );
  }

  UserProfile copyWith({
    String? handle,
    String? phone,
    String? email,
    int? joinedYear,
  }) {
    return UserProfile(
      handle: handle ?? this.handle,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      joinedYear: joinedYear ?? this.joinedYear,
    );
  }
}
