import 'dart:convert';

class SupportTicketModel {
  final String ticketId;
  final String userHandle;
  final String phone;
  final String category;
  final String priority;
  final String subject;
  final String description;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int estimatedHours;
  final String? adminNotes;

  const SupportTicketModel({
    required this.ticketId,
    required this.userHandle,
    required this.phone,
    required this.category,
    required this.priority,
    required this.subject,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.estimatedHours,
    this.adminNotes,
  });

  bool get isUrgent => priority.toLowerCase() == 'urgent';

  bool get isResolved =>
      status.toLowerCase() == 'resolved' || status.toLowerCase() == 'closed';

  int get statusStepIndex {
    switch (status.toLowerCase()) {
      case 'submitted':
        return 0;
      case 'under_review':
        return 1;
      case 'in_progress':
        return 2;
      case 'resolved':
      case 'closed':
        return 3;
      default:
        return 1;
    }
  }

  String get statusDisplayName {
    switch (status.toLowerCase()) {
      case 'submitted':
        return 'Ticket Received';
      case 'under_review':
        return 'Under Review';
      case 'in_progress':
        return 'Agent Assigned';
      case 'resolved':
        return 'Resolved';
      case 'closed':
        return 'Closed';
      default:
        return 'Under Review';
    }
  }

  String get priorityDisplayName {
    return isUrgent ? 'Urgent (2h SLA)' : 'Normal (24h SLA)';
  }

  SupportTicketModel copyWith({
    String? ticketId,
    String? userHandle,
    String? phone,
    String? category,
    String? priority,
    String? subject,
    String? description,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? estimatedHours,
    String? adminNotes,
  }) {
    return SupportTicketModel(
      ticketId: ticketId ?? this.ticketId,
      userHandle: userHandle ?? this.userHandle,
      phone: phone ?? this.phone,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      subject: subject ?? this.subject,
      description: description ?? this.description,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      estimatedHours: estimatedHours ?? this.estimatedHours,
      adminNotes: adminNotes ?? this.adminNotes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ticketId': ticketId,
      'userHandle': userHandle,
      'phone': phone,
      'category': category,
      'priority': priority,
      'subject': subject,
      'description': description,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'estimatedHours': estimatedHours,
      'adminNotes': adminNotes,
    };
  }

  factory SupportTicketModel.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is DateTime) return val;
      if (val is String && val.isNotEmpty) {
        final parsed = DateTime.tryParse(val);
        if (parsed != null) return parsed.isUtc ? parsed.toLocal() : parsed;
      }
      return DateTime.now();
    }

    return SupportTicketModel(
      ticketId: (map['ticketId'] ?? map['ticket_id'] ?? '').toString(),
      userHandle: (map['userHandle'] ?? map['user_handle'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      category: (map['category'] ?? 'General').toString(),
      priority: (map['priority'] ?? 'normal').toString(),
      subject: (map['subject'] ?? '').toString(),
      description: (map['description'] ?? map['feedback_text'] ?? '').toString(),
      status: (map['status'] ?? 'under_review').toString(),
      createdAt: parseDate(map['createdAt'] ?? map['created_at']),
      updatedAt: parseDate(map['updatedAt'] ?? map['updated_at'] ?? map['createdAt']),
      estimatedHours: (map['estimatedHours'] as num?)?.toInt() ??
          ((map['priority'] == 'urgent') ? 2 : 24),
      adminNotes: map['adminNotes'] as String?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory SupportTicketModel.fromJson(String source) =>
      SupportTicketModel.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
