import 'package:flutter/foundation.dart' show immutable;

/// Immutable model representing a user's public profile data.
@immutable
class UserProfile {
  final String handle;
  final String? phone;
  final String? email;
  final int joinedYear;
  final DateTime? joinedDate;

  const UserProfile({
    required this.handle,
    this.phone,
    this.email,
    required this.joinedYear,
    this.joinedDate,
  });

  String get joinedFormatted {
    if (joinedDate != null) {
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      final m = joinedDate!.month;
      if (m >= 1 && m <= 12) {
        return '${months[m - 1]} ${joinedDate!.year}';
      }
      return '${joinedDate!.year}';
    }
    return '$joinedYear';
  }

  factory UserProfile.fromMap(
    Map<String, dynamic> data, {
    String fallbackHandle = '',
  }) {
    final handle = (data['handle'] as String?)?.trim() ?? fallbackHandle;
    final rawPhone = (data['phone'] ?? data['phoneNumber'] ?? data['mobile'] as String?)?.toString().trim();
    final rawEmail = (data['email'] as String?)?.trim();
    final createdAt = data['createdAt'];

    DateTime? joinedDt;
    int year = DateTime.now().year;
    if (createdAt != null) {
      try {
        if (createdAt is DateTime) {
          joinedDt = createdAt;
        } else if (createdAt.runtimeType.toString().contains('Timestamp')) {
          joinedDt = (createdAt as dynamic).toDate() as DateTime;
        } else if (createdAt is String) {
          joinedDt = DateTime.tryParse(createdAt);
        } else if (createdAt is int) {
          joinedDt = DateTime.fromMillisecondsSinceEpoch(createdAt);
        }
        if (joinedDt != null) {
          year = joinedDt.year;
        }
      } catch (_) {}
    }

    return UserProfile(
      handle: handle,
      phone: (rawPhone == null || rawPhone.isEmpty) ? null : rawPhone,
      email: (rawEmail == null || rawEmail.isEmpty) ? null : rawEmail,
      joinedYear: year,
      joinedDate: joinedDt,
    );
  }

  UserProfile copyWith({
    String? handle,
    String? phone,
    String? email,
    int? joinedYear,
    DateTime? joinedDate,
  }) {
    return UserProfile(
      handle: handle ?? this.handle,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      joinedYear: joinedYear ?? this.joinedYear,
      joinedDate: joinedDate ?? this.joinedDate,
    );
  }
}
