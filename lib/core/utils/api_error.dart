String extractApiError(dynamic body, String fallback) {
  if (body == null) {
    return fallback;
  }

  if (body is String) {
    final trimmed = body.trim();
    return trimmed.isNotEmpty ? trimmed : fallback;
  }

  if (body is Map) {
    final error = body['error'];
    if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }
    if (error is Map) {
      final msg = error['message'] ?? error['detail'] ?? error['error'];
      if (msg != null && msg.toString().trim().isNotEmpty) {
        return msg.toString().trim();
      }
    }

    final detail = body['detail'];
    if (detail != null && detail.toString().trim().isNotEmpty) {
      return detail.toString().trim();
    }

    final message = body['message'];
    if (message != null && message.toString().trim().isNotEmpty) {
      return message.toString().trim();
    }

    final msg = body['msg'];
    if (msg != null && msg.toString().trim().isNotEmpty) {
      return msg.toString().trim();
    }
  }

  return fallback;
}
