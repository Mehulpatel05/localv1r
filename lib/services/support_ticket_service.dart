import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/support_ticket_model.dart';
import 'auth_service.dart';

class SupportTicketService {
  static final SupportTicketService instance = SupportTicketService._internal();
  factory SupportTicketService() => instance;
  SupportTicketService._internal();

  final ValueNotifier<List<SupportTicketModel>> ticketsNotifier =
      ValueNotifier<List<SupportTicketModel>>([]);

  String _cleanHandle(String raw) => raw.replaceAll('@', '').trim().toLowerCase();

  String _storageKey(String userHandle) =>
      'support_tickets_cache_${_cleanHandle(userHandle)}';

  Future<List<SupportTicketModel>> loadTickets(String userHandle) async {
    final clean = _cleanHandle(userHandle);
    if (clean.isEmpty || clean == 'guest') {
      ticketsNotifier.value = [];
      return [];
    }

    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_storageKey(clean));
    List<SupportTicketModel> list = [];

    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson) as List<dynamic>;
        list = decoded
            .map((item) => SupportTicketModel.fromMap(item as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('[SupportTicketService] loadTickets json parse error: $e');
      }
    }

    list = _applySimulatedProgress(list);
    ticketsNotifier.value = List.unmodifiable(list);
    return list;
  }

  List<SupportTicketModel> _applySimulatedProgress(List<SupportTicketModel> original) {
    final now = DateTime.now();
    return original.map((t) {
      if (t.isResolved) return t;

      final elapsed = now.difference(t.createdAt);
      if (t.status == 'submitted' && elapsed.inMinutes >= 3) {
        return t.copyWith(
          status: 'under_review',
          updatedAt: t.createdAt.add(const Duration(minutes: 3)),
        );
      } else if ((t.status == 'submitted' || t.status == 'under_review') &&
          elapsed.inMinutes >= (t.isUrgent ? 15 : 45)) {
        return t.copyWith(
          status: 'in_progress',
          updatedAt: t.createdAt.add(Duration(minutes: t.isUrgent ? 15 : 45)),
        );
      }
      return t;
    }).toList();
  }

  Future<void> saveTicket(SupportTicketModel ticket) async {
    final clean = _cleanHandle(ticket.userHandle);
    if (clean.isEmpty) return;

    final current = await loadTickets(clean);
    final updated = List<SupportTicketModel>.from(current);

    final existingIndex = updated.indexWhere((t) => t.ticketId == ticket.ticketId);
    if (existingIndex != -1) {
      updated[existingIndex] = ticket;
    } else {
      updated.insert(0, ticket);
    }

    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(updated.map((t) => t.toMap()).toList());
    await prefs.setString(_storageKey(clean), encoded);

    ticketsNotifier.value = List.unmodifiable(updated);
  }

  Future<void> updateTicketStatus(
    String userHandle,
    String ticketId,
    String newStatus, {
    String? adminNotes,
  }) async {
    final clean = _cleanHandle(userHandle);
    final current = await loadTickets(clean);
    final updated = List<SupportTicketModel>.from(current);

    final idx = updated.indexWhere((t) => t.ticketId == ticketId);
    if (idx != -1) {
      updated[idx] = updated[idx].copyWith(
        status: newStatus,
        updatedAt: DateTime.now(),
        adminNotes: adminNotes ?? updated[idx].adminNotes,
      );

      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(updated.map((t) => t.toMap()).toList());
      await prefs.setString(_storageKey(clean), encoded);

      ticketsNotifier.value = List.unmodifiable(updated);
    }
  }

  Future<void> syncWithBackend(String userHandle) async {
    final clean = _cleanHandle(userHandle);
    if (clean.isEmpty || clean == 'guest') return;

    try {
      final token = await AuthService.instance.getAccessToken();
      final uri = Uri.parse('${AuthService.baseUrl}/feedback/my-tickets');
      final res = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final rawTickets = (body['tickets'] as List<dynamic>?) ?? [];
        if (rawTickets.isNotEmpty) {
          final serverTickets = rawTickets
              .map((t) => SupportTicketModel.fromMap(t as Map<String, dynamic>))
              .toList();

          final localTickets = await loadTickets(clean);
          final mergedMap = <String, SupportTicketModel>{};

          for (final t in localTickets) {
            mergedMap[t.ticketId] = t;
          }
          for (final st in serverTickets) {
            if (st.ticketId.isNotEmpty) {
              mergedMap[st.ticketId] = st;
            }
          }

          final mergedList = mergedMap.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final prefs = await SharedPreferences.getInstance();
          final encoded = jsonEncode(mergedList.map((t) => t.toMap()).toList());
          await prefs.setString(_storageKey(clean), encoded);

          ticketsNotifier.value = List.unmodifiable(mergedList);
        }
      }
    } catch (_) {}
  }
}
