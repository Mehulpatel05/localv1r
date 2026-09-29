import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/models/user_profile.dart';
import '../../services/r2_storage_service.dart';
import '../../services/audio_upload_service.dart';
import '../../services/presence_service.dart';
import '../../services/notification_service.dart';
import '../../services/direct_chat_service.dart';
import '../../services/friend_repository.dart';
import '../../models/call_model.dart';
import '../../services/webrtc_call_service.dart';
import '../../services/token_decision_engine.dart';
import '../../core/action_state/action_state_provider.dart';
import '../../core/widgets/media_attachment_picker.dart';
import '../../main.dart';
import 'call_screen.dart';
import '../profile/other_user_profile_sheet.dart';
import 'widgets/image_group_bubble.dart';
import 'widgets/voice_note_bubble.dart';
import 'widgets/reply_preview_banner.dart';
import 'widgets/quoted_message_widget.dart';
import 'widgets/swipe_to_reply_wrapper.dart';
import '../../core/services/app_image_cache_service.dart';

class _PendingImageUpload {
  final String id;
  final List<File> files;
  final String caption;
  final DateTime timestamp;
  bool isFailed;
  bool isUploading;

  _PendingImageUpload({
    required this.id,
    required this.files,
    required this.caption,
    required this.timestamp,
    this.isFailed = false,
    this.isUploading = true,
  });
}

class _OptimisticTextMessage {
  String id;
  final String content;
  final String senderHandle;
  final String? senderUid;
  final DateTime timestamp;
  final Map<String, dynamic>? replyTo;
  String status;

  _OptimisticTextMessage({
    required this.id,
    required this.content,
    required this.senderHandle,
    this.senderUid,
    required this.timestamp,
    this.replyTo,
    this.status = 'sending',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'content': content,
    'senderHandle': senderHandle,
    'senderUid': senderUid,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'status': status,
    'type': 'text',
    if (replyTo != null) 'replyTo': replyTo,
    'isOptimistic': true,
  };
}

class PersonalChatScreen extends StatefulWidget {
  final String currentUserHandle;
  final String partnerHandle;

  const PersonalChatScreen({
    super.key,
    required this.currentUserHandle,
    required this.partnerHandle,
  });

  @override
  State<PersonalChatScreen> createState() => _PersonalChatScreenState();
}

class _PersonalChatScreenState extends State<PersonalChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late String _chatId;
  int _messageLimit = 40;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  final List<_OptimisticTextMessage> _optimisticMessages = [];
  final List<_PendingImageUpload> _pendingUploads = [];

  // Streams
  Stream<List<Map<String, dynamic>>>? _messagesStream;
  Stream<UserPresence>? _presenceStream;

  // Voice note recording state (ValueNotifiers decoupled from whole screen setState)
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isSendingVoice = false;
  String? _recordingPath;
  Timer? _recordingTimer;
  final ValueNotifier<int> _recordingSecondsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<List<double>> _recordingAmplitudesNotifier = ValueNotifier<List<double>>([]);
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  // Swipe-to-reply state
  Map<String, dynamic>? _replyingTo; // {messageId, senderHandle, previewText}

  // Multi-Message Selection State
  final Set<String> _selectedMessageIds = {};
  final Map<String, Map<String, dynamic>> _selectedMessagesData = {};
  String? _editingMessageId;
  String? _editingOriginalContent;

  bool get _isSelectionMode => _selectedMessageIds.isNotEmpty;

  // Track message doc IDs for scroll-to-reply
  final Map<String, int> _messageIndexMap = {};
  String? _highlightedMessageId;

  // Pre-cached chat metadata for zero-latency sending
  bool _isBlocked = false;

  // Track already-animated messages to eliminate screen flickering / re-animation on polling
  final Set<String> _animatedMessageIds = {};

  // Live typing state
  Timer? _typingDebounceTimer;
  bool _isTypingReported = false;

  // Media picker animation state
  bool _isMediaPickerOpen = false;

  // Call log pulse animation state
  String? _pulsingCallLogId;

  @override
  void initState() {
    super.initState();
    _chatId = _getChatId(widget.currentUserHandle, widget.partnerHandle);
    NotificationService().activeChatPartnerHandle = widget.partnerHandle.replaceAll('@', '').trim();
    _initStreams();
    _scrollController.addListener(_scrollListener);
    _initChatCache();
    _messageController.addListener(_onTextChanged);
    _markChatAsRead();
    _checkVoiceCheckpoint();
  }

  void _fireMarkChatRead() {
    DirectChatService.instance.markChatRead(_chatId, widget.currentUserHandle).catchError((_) => false);
  }

  void _initStreams() {
    _messagesStream = DirectChatService.instance.pollMessagesStream(
      _chatId,
      limit: _messageLimit,
      userHandle: widget.currentUserHandle,
    );
    _presenceStream = PresenceService.instance.getPresenceStream(widget.partnerHandle);
  }

  void _onTextChanged() {
    // Note: Do NOT call setState here! The send/mic toggle uses ValueListenableBuilder
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      if (!_isTypingReported) {
        _isTypingReported = true;
        _updateTypingStatus(true);
      }
      _typingDebounceTimer?.cancel();
      _typingDebounceTimer = Timer(const Duration(seconds: 5), () {
        if (_isTypingReported) {
          _isTypingReported = false;
          _updateTypingStatus(false);
        }
      });
    } else {
      if (_isTypingReported) {
        _isTypingReported = false;
        _typingDebounceTimer?.cancel();
        _updateTypingStatus(false);
      }
    }
  }

  void _updateTypingStatus(bool isTyping) {
    // Typing status via presence if needed
  }

  Future<void> _initChatCache() async {
    final cleanPartner = widget.partnerHandle.replaceAll('@', '').trim();
    try {
      final repo = FriendRepository()..currentUserHandle = widget.currentUserHandle;
      final blocked = await repo.isBlocked(cleanPartner);
      if (mounted) {
        setState(() {
          _isBlocked = blocked;
        });
      }
    } catch (_) {}
  }

  void _scrollListener() {
    if (_scrollController.hasClients &&
        !_isLoadingMore &&
        _hasMoreMessages &&
        _scrollController.position.maxScrollExtent > 200 &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100) {
      _loadMoreMessages();
    }
  }

  void _loadMoreMessages() {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    setState(() {
      _messageLimit += 30;
      _messagesStream = DirectChatService.instance.pollMessagesStream(
        _chatId,
        limit: _messageLimit,
        userHandle: widget.currentUserHandle,
      );
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _isLoadingMore = false;
      }
    });
  }

  @override
  void dispose() {
    final cleanPartner = widget.partnerHandle.replaceAll('@', '').trim();
    if (NotificationService().activeChatPartnerHandle == cleanPartner) {
      NotificationService().activeChatPartnerHandle = null;
    }
    _typingDebounceTimer?.cancel();
    if (_isTypingReported) {
      _updateTypingStatus(false);
    }
    _messageController.removeListener(_onTextChanged);
    _amplitudeSubscription?.cancel();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _recordingSecondsNotifier.dispose();
    _recordingAmplitudesNotifier.dispose();
    _messageController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getChatId(String user1, String user2) {
    final u1 = user1.replaceAll('@', '').trim().toLowerCase();
    final u2 = user2.replaceAll('@', '').trim().toLowerCase();
    final users = [u1, u2]..sort();
    return '${users[0]}_${users[1]}';
  }

  Future<void> _markChatAsRead() async {
    try {
      await DirectChatService.instance.markChatRead(_chatId, widget.currentUserHandle);
    } catch (_) {}
  }

  Future<void> _startCall(CallType type) async {
    final cleanPartner = widget.partnerHandle.replaceAll('@', '').trim();
    if (cleanPartner.isEmpty) return;

    // ⚡ Phase 1 & 3: 2-Step calling check (JWT ban check + in-memory block check)
    final canCall = TokenDecisionEngine.instance.canCallUserSync(cleanPartner);
    final isBlockedInState = ActionStateProvider.instance.isBlocked(cleanPartner);
    if (!canCall || isBlockedInState || _isBlocked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot initiate call. You or the recipient may be restricted or blocked.'),
            backgroundColor: Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    HapticFeedback.lightImpact();

    // 1. Generate callId synchronously in memory (<1ms)
    final callId = 'call_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(999999)}';

    final initialCall = CallModel(
      callId: callId,
      callerHandle: widget.currentUserHandle,
      callerUid: widget.currentUserHandle,
      receiverHandle: cleanPartner,
      receiverUid: cleanPartner,
      callType: type,
      status: CallStatus.calling,
      createdAt: DateTime.now(),
    );

    // 2. Transition immediately into CallScreen (<16ms) with zero perceived latency
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(
            call: initialCall,
            currentUserHandle: widget.currentUserHandle,
            isCaller: true,
          ),
          fullscreenDialog: true,
        ),
      );
    }

    // 3. Trigger makeCall in background with pre-allocated callId
    () async {
      try {
        await WebRtcCallService.instance.makeCall(
          callerHandle: widget.currentUserHandle,
          receiverHandle: cleanPartner,
          callType: type,
          existingCallId: callId,
        );
      } catch (e) {
        debugPrint('Error starting call: $e');
        final rawMsg = e.toString();
        final displayMsg = rawMsg.startsWith('Exception: ')
            ? rawMsg.substring('Exception: '.length)
            : rawMsg;

        final currentCtx = navigatorKey.currentContext;
        if (currentCtx != null && currentCtx.mounted) {
          ScaffoldMessenger.of(currentCtx).showSnackBar(
            SnackBar(
              content: Text(displayMsg),
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.of(currentCtx).maybePop();
        }
        WebRtcCallService.instance.cleanup();
      }
    }();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final replySnapshot = _replyingTo; // snapshot before async gap
    final cleanPartner = widget.partnerHandle.replaceAll('@', '').trim();
    final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim();

    // 1. Instant optimistic UI feedback (<10ms)
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final optimisticMsg = _OptimisticTextMessage(
      id: tempId,
      content: text,
      senderHandle: cleanMe,
      senderUid: cleanMe,
      timestamp: DateTime.now(),
      replyTo: replySnapshot,
      status: 'sending',
    );

    _messageController.clear();
    setState(() {
      _optimisticMessages.insert(0, optimisticMsg);
      _replyingTo = null;
    });
    HapticFeedback.lightImpact();

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }

    if (_isTypingReported) {
      _isTypingReported = false;
      _typingDebounceTimer?.cancel();
      _updateTypingStatus(false);
    }

    // 2. Perform write in background (non-blocking)
    _performSendMessageBackground(optimisticMsg, text, replySnapshot, cleanMe, cleanPartner);
  }

  Future<void> _performSendMessageBackground(
    _OptimisticTextMessage optimisticMsg,
    String text,
    Map<String, dynamic>? replySnapshot,
    String cleanMe,
    String cleanPartner,
  ) async {
    try {
      if (_isBlocked) {
        if (mounted) {
          setState(() {
            optimisticMsg.status = 'failed';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot send message. User is blocked.'),
              backgroundColor: Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final res = await DirectChatService.instance.sendMessage(
        sender: cleanMe,
        receiver: cleanPartner,
        content: text,
        messageType: 'text',
      );

      if (res != null && res['success'] == true) {
        final realId = res['messageId'] as String?;
        if (mounted) {
          setState(() {
            optimisticMsg.status = 'sent';
            if (realId != null && realId.isNotEmpty) {
              optimisticMsg.id = realId;
              _animatedMessageIds.add(realId);
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            optimisticMsg.status = 'failed';
          });
        }
      }

      // Dispatch notification
      NotificationService().sendNotification(
        targetHandle: cleanPartner,
        title: '@$cleanMe',
        body: text,
        data: {
          'type': 'chat',
          'senderHandle': cleanMe,
          'partnerHandle': cleanMe,
          'chatId': _chatId,
        },
      );
    } catch (e) {
      debugPrint('[Chat] Send message background error: $e');
      if (mounted) {
        setState(() {
          optimisticMsg.status = 'failed';
        });
      }
    }
  }

  // ⚡ Fix 7: Retry failed optimistic message
  void _retrySendMessage(String msgId) {
    final idx = _optimisticMessages.indexWhere((m) => m.id == msgId);
    if (idx != -1) {
      final msg = _optimisticMessages[idx];
      setState(() {
        msg.status = 'sending';
      });
      final cleanPartner = widget.partnerHandle.replaceAll('@', '').trim();
      final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim();
      _performSendMessageBackground(msg, msg.content, msg.replyTo, cleanMe, cleanPartner);
    }
  }

  // ⚡ Fix 9: Voice note checkpointing keys & methods
  static const String _kVoiceCheckpointPathKey = 'voice_note_checkpoint_path';
  static const String _kVoiceCheckpointChatIdKey = 'voice_note_checkpoint_chat_id';
  static const String _kVoiceCheckpointTimeKey = 'voice_note_checkpoint_time';

  Future<void> _checkVoiceCheckpoint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(_kVoiceCheckpointPathKey);
      final chatId = prefs.getString(_kVoiceCheckpointChatIdKey);
      final time = prefs.getInt(_kVoiceCheckpointTimeKey);

      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          final length = await file.length();
          final age = time != null
              ? DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(time))
              : const Duration(hours: 2);

          if (length == 0 || age.inHours >= 1) {
            // Clean up stale or zero-byte temp file
            try { await file.delete(); } catch (_) {}
            await prefs.remove(_kVoiceCheckpointPathKey);
            await prefs.remove(_kVoiceCheckpointChatIdKey);
            await prefs.remove(_kVoiceCheckpointTimeKey);
          } else if (chatId == _chatId && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Found interrupted voice recording from previous session'),
                action: SnackBarAction(
                  label: 'Discard',
                  textColor: Colors.white,
                  onPressed: () {
                    try { file.delete(); } catch (_) {}
                    prefs.remove(_kVoiceCheckpointPathKey);
                    prefs.remove(_kVoiceCheckpointChatIdKey);
                    prefs.remove(_kVoiceCheckpointTimeKey);
                  },
                ),
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          await prefs.remove(_kVoiceCheckpointPathKey);
        }
      }
    } catch (e) {
      debugPrint('[VoiceNote] Checkpoint check error: $e');
    }
  }


  Future<void> _pickAndSendImages() async {
    setState(() => _isMediaPickerOpen = true);
    final filesToUpload = await MediaAttachmentPicker.showPickerSheet(
      context: context,
      maxFiles: 8,
    );
    if (mounted) {
      setState(() => _isMediaPickerOpen = false);
    }

    if (filesToUpload.isEmpty) return;

    final caption = _messageController.text.trim();
    _messageController.clear();

    final uploadItem = _PendingImageUpload(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      files: filesToUpload,
      caption: caption,
      timestamp: DateTime.now(),
      isUploading: true,
      isFailed: false,
    );

    setState(() {
      _pendingUploads.insert(0, uploadItem);
    });

    _executeImageUpload(uploadItem);
  }

  Future<void> _executeImageUpload(_PendingImageUpload uploadItem) async {
    setState(() {
      uploadItem.isUploading = true;
      uploadItem.isFailed = false;
    });

    try {
      final uploadFutures = uploadItem.files.map((f) => R2StorageService.uploadImage(f));
      final uploadedUrls = await Future.wait(uploadFutures);
      final validUrls = uploadedUrls.whereType<String>().toList();

      if (validUrls.isEmpty) throw Exception('Image upload failed.');

      final cleanPartner = widget.partnerHandle.replaceAll('@', '').trim();
      final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim();

      if (_isBlocked) {
        throw Exception('Cannot send image. User is blocked.');
      }

      final isGroup = validUrls.length > 1;
      final summaryText = uploadItem.caption.isNotEmpty
          ? uploadItem.caption
          : (isGroup ? '📷 ${validUrls.length} photos' : '📷 Photo');

      final res = await DirectChatService.instance.sendMessage(
        sender: cleanMe,
        receiver: cleanPartner,
        content: uploadItem.caption,
        imageUrl: validUrls.first,
        mediaUrls: validUrls,
        messageType: isGroup ? 'image_group' : 'image',
      );

      if (res != null && res['success'] == true) {
        if (mounted) {
          setState(() {
            _pendingUploads.removeWhere((p) => p.id == uploadItem.id);
          });
        }
      } else {
        throw Exception('Failed to send image message');
      }

      NotificationService().sendNotification(
        targetHandle: cleanPartner,
        title: '@$cleanMe',
        body: summaryText,
        data: {
          'type': 'chat',
          'senderHandle': cleanMe,
          'partnerHandle': cleanMe,
          'chatId': _chatId,
        },
      );
    } catch (e) {
      debugPrint('[ImageUpload] Error: $e');
      if (mounted) {
        setState(() {
          uploadItem.isUploading = false;
          uploadItem.isFailed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image upload failed. Tap retry on bubble.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _retryImageUpload(_PendingImageUpload uploadItem) {
    _executeImageUpload(uploadItem);
  }

  Widget _buildPendingUploadBubble(_PendingImageUpload item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeStr = DateFormat('hh:mm a').format(item.timestamp);
    final isMultiple = item.files.length > 1;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    item.files.first,
                    width: 250,
                    height: 220,
                    fit: BoxFit.cover,
                  ),
                ),
                Container(
                  width: 250,
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                if (item.isUploading)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                  )
                else if (item.isFailed)
                  GestureDetector(
                    onTap: () => _retryImageUpload(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Failed. Tap to retry',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (isMultiple)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_library_rounded, color: Colors.white, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            '+${item.files.length - 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (item.caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                child: Text(
                  item.caption,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontSize: 14,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    item.isFailed
                        ? Icons.error_outline_rounded
                        : Icons.access_time_rounded,
                    size: 13,
                    color: item.isFailed
                        ? const Color(0xFFEF4444)
                        : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp is DateTime) return timestamp.isUtc ? timestamp.toLocal() : timestamp;
    if (timestamp is int) {
      return timestamp > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true).toLocal();
    }
    if (timestamp is String) {
      final numVal = int.tryParse(timestamp);
      if (numVal != null) {
        return numVal > 1000000000000
            ? DateTime.fromMillisecondsSinceEpoch(numVal, isUtc: true).toLocal()
            : DateTime.fromMillisecondsSinceEpoch(numVal * 1000, isUtc: true).toLocal();
      }
      final parsed = DateTime.tryParse(timestamp);
      if (parsed != null) {
        return parsed.isUtc ? parsed.toLocal() : parsed;
      }
      return DateTime.now();
    }
    return DateTime.now();
  }

  String _formatMsgTime(dynamic timestamp) {
    if (timestamp == null) return '';
    final dt = _parseTimestamp(timestamp);
    return DateFormat('hh:mm a').format(dt);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(msgDay).inDays;

    String label;
    if (diff == 0) {
      label = 'Today';
    } else if (diff == 1) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMMM d, y').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  // ── Voice Note Methods ─────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    FocusScope.of(context).unfocus();
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission required to record voice notes.'),
            backgroundColor: Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
        path: path,
      );

      _recordingAmplitudesNotifier.value = [];
      _recordingSecondsNotifier.value = 0;
      _recordingPath = path;

      // Listen to amplitude for waveform
      _amplitudeSubscription?.cancel();
      _amplitudeSubscription =
          _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
        if (!mounted) return;
        // Normalize dBFS (-60..0) to 0..1
        final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
        final list = List<double>.from(_recordingAmplitudesNotifier.value)..add(normalized);
        if (list.length > 40) {
          list.removeAt(0);
        }
        _recordingAmplitudesNotifier.value = list;
      });

      // Timer for seconds counter
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        _recordingSecondsNotifier.value++;
        if (_recordingSecondsNotifier.value >= 120) {
          // Max 2 min
          _stopAndSendVoiceNote();
        }
      });

      // ⚡ Fix 9: Save temp file checkpoint to survive process kill
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kVoiceCheckpointPathKey, path);
      await prefs.setString(_kVoiceCheckpointChatIdKey, _chatId);
      await prefs.setInt(_kVoiceCheckpointTimeKey, DateTime.now().millisecondsSinceEpoch);

      setState(() => _isRecording = true);
      HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('[VoiceNote] Start recording error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start recording: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _stopAndCancelRecording() async {
    _recordingTimer?.cancel();
    _amplitudeSubscription?.cancel();
    await _audioRecorder.stop();

    // ⚡ Fix 9: Clear checkpoint on cancel
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kVoiceCheckpointPathKey);
    await prefs.remove(_kVoiceCheckpointChatIdKey);
    await prefs.remove(_kVoiceCheckpointTimeKey);

    // Delete temp file
    if (_recordingPath != null) {
      final f = File(_recordingPath!);
      if (await f.exists()) await f.delete();
    }
    if (mounted) {
      _recordingSecondsNotifier.value = 0;
      _recordingAmplitudesNotifier.value = [];
      setState(() {
        _isRecording = false;
        _recordingPath = null;
      });
    }
    HapticFeedback.lightImpact();
  }

  Future<void> _stopAndSendVoiceNote() async {
    _recordingTimer?.cancel();
    _amplitudeSubscription?.cancel();

    final path = _recordingPath;

    if (mounted) {
      _recordingSecondsNotifier.value = 0;
      _recordingAmplitudesNotifier.value = [];
      setState(() {
        _isRecording = false;
        _isSendingVoice = true;
        _recordingPath = null;
      });
    }
    HapticFeedback.mediumImpact();

    try {
      final stoppedPath = await _audioRecorder.stop() ?? path;
      if (stoppedPath == null) throw Exception('Recording path is null');

      final file = File(stoppedPath);
      if (!await file.exists()) throw Exception('Recording file not found');

      final cleanPartner = widget.partnerHandle.replaceAll('@', '').trim();
      final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim();

      if (_isBlocked) {
        await file.delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot send message. User is blocked.'),
              backgroundColor: Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Upload audio
      final audioUrl = await AudioUploadService.uploadVoiceNote(file);
      await file.delete();

      if (audioUrl == null || audioUrl.isEmpty) {
        throw Exception('Upload failed — no URL returned');
      }

      final res = await DirectChatService.instance.sendMessage(
        sender: cleanMe,
        receiver: cleanPartner,
        content: '',
        imageUrl: audioUrl,
        mediaUrls: [audioUrl],
        messageType: 'voice_note',
      );

      if (res == null || res['success'] != true) {
        throw Exception('Failed to send voice note');
      }

      NotificationService().sendNotification(
        targetHandle: cleanPartner,
        title: '@$cleanMe',
        body: '🎤 Voice note',
        data: {'type': 'chat', 'senderHandle': cleanMe, 'partnerHandle': cleanMe, 'chatId': _chatId},
      );
    } catch (e) {
      debugPrint('[VoiceNote] Send error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send voice note: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      // ⚡ Fix 9: Clear checkpoint on send finish
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kVoiceCheckpointPathKey);
        await prefs.remove(_kVoiceCheckpointChatIdKey);
        await prefs.remove(_kVoiceCheckpointTimeKey);
      } catch (_) {}
      if (mounted) setState(() => _isSendingVoice = false);
    }
  }

  String _formatRecordingTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Swipe-to-Reply Helper ──────────────────────────────────────────────────

  void _onSwipeToReply(Map<String, dynamic> msg, String msgId) {
    final type = (msg['type'] ?? 'text') as String;
    String preview;
    if (type == 'voice_note') {
      preview = '🎤 Voice note';
    } else if (type == 'image' || type == 'image_group') {
      preview = '📷 Photo';
    } else {
      final content = (msg['content'] ?? '') as String;
      preview = content.length > 80 ? '${content.substring(0, 80)}…' : content;
    }

    final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim();
    final cleanPartner = widget.partnerHandle.replaceAll('@', '').trim();
    final rawSender = (msg['senderHandle'] ?? '').toString().replaceAll('@', '').trim();

    final isMyMsg = rawSender.isNotEmpty && rawSender.toLowerCase() == cleanMe.toLowerCase();

    final canonicalSender = isMyMsg
        ? cleanMe
        : (rawSender.isNotEmpty ? rawSender : cleanPartner);

    setState(() {
      _replyingTo = {
        'messageId': msgId,
        'senderHandle': canonicalSender,
        'senderUid': isMyMsg ? cleanMe : cleanPartner,
        'isMe': isMyMsg,
        'previewText': preview,
        'type': type,
      };
    });
    HapticFeedback.lightImpact();

    // Automatically focus input field & open keyboard (WhatsApp/Instagram UX)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (!_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
        SystemChannels.textInput.invokeMethod('TextInput.show');
        if (_messageController.text.isNotEmpty) {
          _messageController.selection = TextSelection.fromPosition(
            TextPosition(offset: _messageController.text.length),
          );
        }
      }
    });
  }

  void _toggleMessageSelection(String msgId, Map<String, dynamic> msg) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedMessageIds.contains(msgId)) {
        _selectedMessageIds.remove(msgId);
        _selectedMessagesData.remove(msgId);
      } else {
        _selectedMessageIds.add(msgId);
        _selectedMessagesData[msgId] = msg;
      }
    });
  }

  void _clearSelection() {
    if (_selectedMessageIds.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _selectedMessageIds.clear();
        _selectedMessagesData.clear();
      });
    }
  }

  bool _canEditSelectedMessage() {
    if (_selectedMessageIds.length != 1) return false;
    final id = _selectedMessageIds.first;
    final msg = _selectedMessagesData[id];
    if (msg == null) return false;

    if (msg['isDeleted'] == true || msg['deletedForEveryone'] == true) return false;

    final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim().toLowerCase();
    final msgSenderHandle = (msg['senderHandle'] ?? '').toString().replaceAll('@', '').trim().toLowerCase();
    final isMe = msgSenderHandle.isNotEmpty && msgSenderHandle == cleanMe;

    final type = (msg['type'] ?? 'text') as String;
    if (!isMe || type != 'text') return false;

    // ⚡ Fix 5: 15-minute hard limit client validation
    final msgTime = _parseTimestamp(msg['timestamp'] ?? msg['createdAt']);
    final diff = DateTime.now().difference(msgTime);
    if (diff.inSeconds > (15 * 60)) {
      return false;
    }
    return true;
  }

  void _startEditingMessage() {
    if (!_canEditSelectedMessage()) return;
    final singleId = _selectedMessageIds.first;
    final singleMsg = _selectedMessagesData[singleId]!;
    final originalContent = (singleMsg['content'] ?? '') as String;

    setState(() {
      _editingMessageId = singleId;
      _editingOriginalContent = originalContent;
      _messageController.text = originalContent;
      _selectedMessageIds.clear();
      _selectedMessagesData.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (!_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
        SystemChannels.textInput.invokeMethod('TextInput.show');
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
      }
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingMessageId = null;
      _editingOriginalContent = null;
      _messageController.clear();
    });
  }

  Future<void> _saveEditedMessage() async {
    final newText = _messageController.text.trim();
    final editId = _editingMessageId;
    if (editId == null || newText.isEmpty) return;

    if (newText == _editingOriginalContent) {
      _cancelEditing();
      return;
    }

    final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim();
    _cancelEditing();

    try {
      // ⚡ Fix 5: Server-validated 15-minute edit API call
      await DirectChatService.instance.editMessage(
        messageId: editId,
        userHandle: cleanMe,
        newContent: newText,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message edited'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error editing message: $e');
      if (mounted) {
        final errText = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot edit message: $errText'),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _copySelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;

    final entries = _selectedMessagesData.entries.toList();
    entries.sort((a, b) {
      final aTs = _parseTimestamp(a.value['timestamp']);
      final bTs = _parseTimestamp(b.value['timestamp']);
      return aTs.compareTo(bTs);
    });

    final List<String> texts = [];
    for (final entry in entries) {
      final msg = entry.value;
      final type = msg['type'] ?? 'text';
      final content = (msg['content'] ?? '') as String;
      if (content.isNotEmpty) {
        texts.add(content);
      } else if (type == 'voice_note') {
        texts.add('[Voice Note]');
      } else if (type == 'image' || type == 'image_group') {
        texts.add('[Photo]');
      }
    }

    if (texts.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: texts.join('\n\n')));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            texts.length == 1
                ? 'Message copied to clipboard'
                : '${texts.length} messages copied to clipboard',
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    _clearSelection();
  }

  void _forwardSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;

    final entries = _selectedMessagesData.entries.toList();
    entries.sort((a, b) {
      final aTs = _parseTimestamp(a.value['timestamp']);
      final bTs = _parseTimestamp(b.value['timestamp']);
      return aTs.compareTo(bTs);
    });

    final selectedList = entries
        .map((e) => e.value)
        .where((m) => m['isDeleted'] != true && m['deletedForEveryone'] != true)
        .toList();
    _clearSelection();

    if (selectedList.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ForwardMessageSheet(
        messagesToForward: selectedList,
        currentUserHandle: widget.currentUserHandle,
      ),
    );
  }

  void _deleteSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim().toLowerCase();

    bool allFromMe = true;
    bool allWithin48Hours = true;
    for (final msg in _selectedMessagesData.values) {
      final msgSenderHandle = (msg['senderHandle'] ?? '').toString().replaceAll('@', '').trim().toLowerCase();
      if (msgSenderHandle != cleanMe) {
        allFromMe = false;
      }
      final msgTime = _parseTimestamp(msg['timestamp'] ?? msg['createdAt']);
      if (DateTime.now().difference(msgTime).inSeconds > (48 * 3600)) {
        allWithin48Hours = false;
      }
    }

    final canDeleteForEveryone = allFromMe && allWithin48Hours;
    final count = _selectedMessageIds.length;
    final idsToDelete = Set<String>.from(_selectedMessageIds);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete $count message${count > 1 ? 's' : ''}?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        content: Text(
          canDeleteForEveryone
              ? 'You can delete these messages just for yourself, or delete them for everyone in this chat.'
              : (allFromMe && !allWithin48Hours
                  ? 'Messages older than 48 hours cannot be deleted for everyone. They will be removed from your chat view.'
                  : 'These messages will be removed from your chat view.'),
          style: TextStyle(
            fontSize: 14,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executeDeleteSelected(idsToDelete, forEveryone: false);
            },
            child: const Text(
              'Delete for me',
              style: TextStyle(
                color: Color(0xFF2563EB),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (canDeleteForEveryone)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _executeDeleteSelected(idsToDelete, forEveryone: true);
              },
              child: const Text(
                'Delete for everyone',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _executeDeleteSelected(Set<String> msgIds, {required bool forEveryone}) async {
    _clearSelection();
    final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim();

    // Immediately remove from optimistic messages if present
    if (mounted) {
      setState(() {
        _optimisticMessages.removeWhere((m) => msgIds.contains(m.id));
      });
    }

    try {
      for (final id in msgIds) {
        await DirectChatService.instance.deleteMessage(id, cleanMe, forEveryone: forEveryone);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              forEveryone
                  ? 'Deleted ${msgIds.length} message${msgIds.length > 1 ? 's' : ''} for everyone'
                  : 'Deleted ${msgIds.length} message${msgIds.length > 1 ? 's' : ''} for me',
            ),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting messages: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete messages: $e'),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildCallLogBubble(Map<String, dynamic> msg, String msgId, bool isMe) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedMessageIds.contains(msgId);
    final isSelectionActive = _isSelectionMode;

    final callType = (msg['callType'] ?? 'audio').toString().toLowerCase();
    final callStatus = (msg['callStatus'] ?? 'ended').toString().toLowerCase();
    final durationSeconds = (msg['durationSeconds'] as num?)?.toInt() ?? 0;
    final isVideo = callType == 'video';
    final timeStr = _formatMsgTime(msg['timestamp']);

    final isMissed = callStatus == 'missed';
    final isDeclined = callStatus == 'declined';
    final isBusy = callStatus == 'busy';
    final isOutgoing = isMe;

    // Title formulation matching user screenshot exactly
    String title;
    if (isOutgoing) {
      if (isMissed || isDeclined) {
        title = 'Cancelled ${isVideo ? 'video' : 'voice'} call';
      } else if (isBusy) {
        title = 'User busy';
      } else {
        title = 'Outgoing ${isVideo ? 'video' : 'voice'} call';
      }
    } else {
      if (isMissed) {
        title = 'Missed ${isVideo ? 'video' : 'voice'} call';
      } else if (isDeclined) {
        title = 'Declined ${isVideo ? 'video' : 'voice'} call';
      } else if (isBusy) {
        title = 'Missed ${isVideo ? 'video' : 'voice'} call';
      } else {
        title = 'Incoming ${isVideo ? 'video' : 'voice'} call';
      }
    }

    // Subtitle formatting: "01:44 PM . 11s" or "02:01 PM"
    String subtitle = timeStr;
    if (durationSeconds > 0) {
      final m = durationSeconds ~/ 60;
      final s = durationSeconds % 60;
      final durStr = m > 0 ? '${m}m ${s}s' : '${s}s';
      subtitle = '$timeStr . $durStr';
    }

    // Determine colors & styling per user screenshot
    final bool showMissedStyle = !isOutgoing && (isMissed || isDeclined || isBusy);

    // Bubble Background
    final Color bubbleColor;
    if (isOutgoing) {
      // Outgoing caller: sleek dark charcoal/black container
      bubbleColor = const Color(0xFF18181B);
    } else if (showMissedStyle) {
      // Missed incoming calls: soft pastel red/pink
      bubbleColor = isDark ? const Color(0xFF2C1518) : const Color(0xFFFEE2E2);
    } else {
      // Answered incoming calls: soft grey-blue/off-white
      bubbleColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    }

    // Icon circle badge background
    final Color badgeColor;
    final Color iconColor;
    final IconData iconData;

    if (isOutgoing) {
      badgeColor = const Color(0xFF27272A);
      if (isMissed || isDeclined || isBusy) {
        iconColor = const Color(0xFF94A3B8);
        iconData = isVideo ? Icons.videocam_rounded : Icons.call_made_rounded;
      } else {
        iconColor = const Color(0xFF10B981);
        iconData = isVideo ? Icons.videocam_rounded : Icons.call_made_rounded;
      }
    } else if (showMissedStyle) {
      badgeColor = isDark ? const Color(0xFF4C1D24) : const Color(0xFFFECDD3);
      iconColor = const Color(0xFFDC2626);
      iconData = isVideo ? Icons.videocam_off_rounded : Icons.phone_missed_rounded;
    } else {
      badgeColor = const Color(0xFFD1FAE5);
      iconColor = const Color(0xFF059669);
      iconData = isVideo ? Icons.videocam_rounded : Icons.call_received_rounded;
    }

    // Typography colors
    final Color titleColor;
    final Color subtitleColor;
    if (isOutgoing) {
      titleColor = Colors.white;
      subtitleColor = const Color(0xFFA1A1AA);
    } else if (showMissedStyle) {
      titleColor = isDark ? const Color(0xFFFFB4AB) : const Color(0xFF0F172A);
      subtitleColor = isDark ? const Color(0xFFF87171) : const Color(0xFF64748B);
    } else {
      titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
      subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    }

    final bubbleBody = Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () {
          if (isSelectionActive) {
            _toggleMessageSelection(msgId, msg);
            return;
          }
          setState(() => _pulsingCallLogId = msgId);
          HapticFeedback.lightImpact();
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) {
              setState(() => _pulsingCallLogId = null);
              _startCall(isVideo ? CallType.video : CallType.audio);
            }
          });
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: _pulsingCallLogId == msgId ? 1.25 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    iconData,
                    color: iconColor,
                    size: isVideo ? 21 : 19,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final rowContent = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (isSelectionActive)
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF2563EB)
                      : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                  width: 1.8,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : null,
            ),
          ),
        Expanded(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: isSelectionActive && !isSelected ? 0.55 : 1.0,
            child: bubbleBody,
          ),
        ),
      ],
    );

    final selectedBgColor = isSelected
        ? (isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.7)
            : const Color(0xFFEBF4FF))
        : Colors.transparent;

    return Material(
      color: selectedBgColor,
      child: InkWell(
        onTap: isSelectionActive ? () => _toggleMessageSelection(msgId, msg) : null,
        onLongPress: () => _toggleMessageSelection(msgId, msg),
        splashColor: const Color(0xFF2563EB).withValues(alpha: 0.1),
        highlightColor: const Color(0xFF2563EB).withValues(alpha: 0.05),
        child: rowContent,
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, String msgId, bool isMe) {
    if (msg['type'] == 'call_log') {
      return _buildCallLogBubble(msg, msgId, isMe);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim();

    // 1. If deleted for me, hide completely
    final deletedForUsers = (msg['deletedForUsers'] as List?)
        ?.map((u) => u.toString().replaceAll('@', '').trim().toLowerCase())
        .toList();
    if (deletedForUsers != null && deletedForUsers.contains(cleanMe.toLowerCase())) {
      return const SizedBox.shrink();
    }

    // 2. If revoked / deleted for everyone, show WhatsApp-style placeholder
    final isDeleted = msg['isDeleted'] == true || msg['deletedForEveryone'] == true;
    if (isDeleted) {
      final isSelected = _selectedMessageIds.contains(msgId);
      final isSelectionActive = _isSelectionMode;
      final timeStr = _formatMsgTime(msg['timestamp']);

      final tombstoneContent = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.block_rounded,
              size: 15,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                isMe ? 'You deleted this message' : 'This message was deleted',
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  fontSize: 13.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            if (timeStr.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                timeStr,
                style: TextStyle(
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      );

      final bubbleWidget = Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3.5),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
              bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
            ),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              width: 1.0,
            ),
          ),
          child: AbsorbPointer(
            absorbing: isSelectionActive,
            child: tombstoneContent,
          ),
        ),
      );

      final rowContent = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isSelectionActive)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF2563EB)
                        : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                    width: 1.8,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : null,
              ),
            ),
          Expanded(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: isSelectionActive && !isSelected ? 0.55 : 1.0,
              child: bubbleWidget,
            ),
          ),
        ],
      );

      final selectedBgColor = isSelected
          ? (isDark
              ? const Color(0xFF1E293B).withValues(alpha: 0.7)
              : const Color(0xFFEBF4FF))
          : Colors.transparent;

      return Material(
        color: selectedBgColor,
        child: InkWell(
          onTap: isSelectionActive ? () => _toggleMessageSelection(msgId, msg) : null,
          onLongPress: () => _toggleMessageSelection(msgId, msg),
          splashColor: const Color(0xFF2563EB).withValues(alpha: 0.1),
          highlightColor: const Color(0xFF2563EB).withValues(alpha: 0.05),
          child: rowContent,
        ),
      );
    }

    final isSelected = _selectedMessageIds.contains(msgId);
    final isSelectionActive = _isSelectionMode;
    final isEdited = msg['isEdited'] == true;

    final content = (msg['content'] ?? '') as String;
    final imageUrl = msg['imageUrl'] as String?;
    final rawMediaUrls = msg['mediaUrls'];
    final timeStr = _formatMsgTime(msg['timestamp']);
    final isVoiceNote = msg['type'] == 'voice_note';
    final isRead = msg['isRead'] == true || msg['status'] == 'read';
    final status = (msg['status'] ?? 'sent') as String;
    final isForwarded = msg['isForwarded'] == true;

    final List<String> mediaUrls = [];
    if (rawMediaUrls is List) {
      for (final u in rawMediaUrls) {
        if (u != null && u.toString().isNotEmpty) {
          mediaUrls.add(u.toString());
        }
      }
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      mediaUrls.add(imageUrl);
    }

    final hasImages = mediaUrls.isNotEmpty;

    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
      bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
    );

    // Reply-to data
    final replyToRaw = msg['replyTo'];
    final replyTo = replyToRaw is Map<String, dynamic> ? replyToRaw : null;
    final quotedSenderRaw = (replyTo?['senderHandle'] ?? '').toString().replaceAll('@', '').trim();
    final isQuotedFromMe = quotedSenderRaw.isNotEmpty &&
        quotedSenderRaw.toLowerCase() == cleanMe.toLowerCase();

    // Build the inner content of the bubble
    Widget bubbleContent;
    if (isVoiceNote) {
      final audioUrl = (msg['audioUrl'] ?? '') as String;
      final durationSecs = (msg['durationSeconds'] as num?)?.toInt() ?? 0;
      final rawWave = msg['waveformData'];
      final List<double> waveform = [];
      if (rawWave is List) {
        for (final v in rawWave) {
          waveform.add((v as num?)?.toDouble() ?? 0.3);
        }
      }
      bubbleContent = Padding(
        padding: const EdgeInsets.only(left: 4, right: 4, top: 6, bottom: 4),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isForwarded)
              _buildForwardedLabel(isMe, isDark),
            if (replyTo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: QuotedMessageWidget(
                  senderHandle: quotedSenderRaw,
                  previewText: (replyTo['previewText'] ?? '') as String,
                  isMe: isMe,
                  isQuotedFromMe: isQuotedFromMe,
                  onTap: () => _scrollToMessage(replyTo['messageId'] as String?),
                ),
              ),
            VoiceNoteBubble(
              audioUrl: audioUrl,
              durationSeconds: durationSecs,
              waveformData: waveform,
              isMe: isMe,
              timeStr: timeStr,
              isRead: isRead,
              status: status,
            ),
          ],
        ),
      );
    } else if (hasImages) {
      bubbleContent = Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isForwarded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: _buildForwardedLabel(isMe, isDark),
            ),
          if (replyTo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: QuotedMessageWidget(
                senderHandle: quotedSenderRaw,
                previewText: (replyTo['previewText'] ?? '') as String,
                isMe: isMe,
                isQuotedFromMe: isQuotedFromMe,
                onTap: () => _scrollToMessage(replyTo['messageId'] as String?),
              ),
            ),
          ImageGroupBubble(
            mediaUrls: mediaUrls,
            caption: content.isNotEmpty ? content : null,
            timeStr: timeStr,
            isMe: isMe,
            messageId: msgId,
            bubbleRadius: bubbleRadius,
            isRead: isRead,
            status: status,
          ),
        ],
      );
    } else {
      bubbleContent = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isForwarded)
              _buildForwardedLabel(isMe, isDark),
            if (replyTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: QuotedMessageWidget(
                  senderHandle: quotedSenderRaw,
                  previewText: (replyTo['previewText'] ?? '') as String,
                  isMe: isMe,
                  isQuotedFromMe: isQuotedFromMe,
                  onTap: () => _scrollToMessage(replyTo['messageId'] as String?),
                ),
              ),
            Text(
              content,
              style: TextStyle(
                color: isMe
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? Colors.white : const Color(0xFF0F172A)),
                fontSize: 14.5,
                height: 1.35,
              ),
            ),
            if (timeStr.isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isEdited) ...[
                    Text(
                      'edited  ',
                      style: TextStyle(
                        color: isMe
                            ? (isDark ? Colors.black45 : Colors.white60)
                            : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: isMe
                          ? (isDark ? Colors.black54 : Colors.white70)
                          : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF94A3B8)),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (isMe) ...[
                    if (status == 'failed') ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _retrySendMessage(msgId),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 13,
                              color: Color(0xFFEF4444),
                            ),
                            SizedBox(width: 2),
                            Text(
                              'Retry',
                              style: TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (status == 'sending') ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: isDark ? Colors.black54 : Colors.white70,
                      ),
                    ] else ...[
                      const SizedBox(width: 4),
                      Icon(
                        isRead
                            ? Icons.done_all_rounded
                            : (status == 'delivered'
                                ? Icons.done_all_rounded
                                : Icons.done_rounded),
                        size: 14,
                        color: isRead
                            ? const Color(0xFF93C5FD)
                            : (isDark ? Colors.black54 : Colors.white70),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ],
        ),
      );
    }

    final isHighlighted = msgId == _highlightedMessageId;

    final bubbleWidget = Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3.5),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * (hasImages ? 0.70 : 0.78),
        ),
        decoration: BoxDecoration(
          color: isHighlighted
              ? const Color(0xFF2563EB).withValues(alpha: isDark ? 0.25 : 0.12)
              : (isMe
                  ? (isDark ? Colors.white : Colors.black)
                  : (isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF4F4F4))),
          borderRadius: bubbleRadius,
          border: Border.all(
            color: isHighlighted
                ? const Color(0xFF2563EB)
                : (isMe
                    ? (isDark ? Colors.white : Colors.black)
                    : (isDark ? const Color(0xFF262626) : const Color(0xFFE6E6E6))),
            width: isHighlighted ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isHighlighted
                  ? const Color(0xFF2563EB).withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.03),
              offset: const Offset(0, 1),
              blurRadius: isHighlighted ? 8 : 3,
            ),
          ],
        ),
        child: AbsorbPointer(
          absorbing: isSelectionActive,
          child: bubbleContent,
        ),
      ),
    );

    final rowContent = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (isSelectionActive)
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF2563EB)
                      : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                  width: 1.8,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : null,
            ),
          ),
        Expanded(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: isSelectionActive && !isSelected ? 0.55 : 1.0,
            child: bubbleWidget,
          ),
        ),
      ],
    );

    final selectedBgColor = isSelected
        ? (isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.7)
            : const Color(0xFFEBF4FF))
        : Colors.transparent;

    final tappableRow = Material(
      color: selectedBgColor,
      child: InkWell(
        onTap: isSelectionActive
            ? () => _toggleMessageSelection(msgId, msg)
            : (status == 'failed' ? () => _retrySendMessage(msgId) : null),
        onLongPress: () => _toggleMessageSelection(msgId, msg),
        splashColor: const Color(0xFF2563EB).withValues(alpha: 0.1),
        highlightColor: const Color(0xFF2563EB).withValues(alpha: 0.05),
        child: rowContent,
      ),
    );

    return SwipeToReplyWrapper(
      key: ValueKey('swipe_reply_$msgId'),
      messageId: msgId,
      isMe: isMe,
      enabled: !isSelectionActive,
      onSwipeReply: () => _onSwipeToReply(msg, msgId),
      child: tappableRow,
    );
  }

  void _scrollToMessage(String? messageId) {
    if (messageId == null) return;
    final idx = _messageIndexMap[messageId];
    if (idx != null && _scrollController.hasClients) {
      final estimatedHeight = 78.0;
      final targetOffset = (idx * estimatedHeight).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
      setState(() {
        _highlightedMessageId = messageId;
      });
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _highlightedMessageId == messageId) {
          setState(() {
            _highlightedMessageId = null;
          });
        }
      });
    }
  }



  Widget _buildEmptyChatPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Color(0xFF2563EB),
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Say hi to @${widget.partnerHandle.replaceAll('@', '')}!',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Send a message to start connecting with your neighbor.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList(List<Map<String, dynamic>> messages) {
    // Automatically evict optimistic messages that have been confirmed in synced messages
    _optimisticMessages.removeWhere((opt) => messages.any((doc) {
      final docId = (doc['id'] ?? doc['messageId'] ?? '').toString();
      if (docId.isNotEmpty && docId == opt.id) return true;
      if (opt.id.startsWith('temp_') && doc['content'] == opt.content && doc['senderHandle'] == opt.senderHandle) {
        return true;
      }
      return false;
    }));

    _messageIndexMap.clear();
    for (int i = 0; i < messages.length; i++) {
      final id = (messages[i]['id'] ?? messages[i]['messageId'] ?? '').toString();
      _messageIndexMap[id] = i + _pendingUploads.length + _optimisticMessages.length;
    }

    final totalCount = _optimisticMessages.length + _pendingUploads.length + messages.length;

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        // 1. In-flight Optimistic Text Messages (newest, shown immediately)
        if (index < _optimisticMessages.length) {
          final optMsg = _optimisticMessages[index];
          final bubble = _buildMessageBubble(optMsg.toMap(), optMsg.id, true);
          final isNew = !_animatedMessageIds.contains(optMsg.id);
          if (isNew) _animatedMessageIds.add(optMsg.id);

          return KeyedSubtree(
            key: ValueKey('opt_${optMsg.id}'),
            child: isNew ? _AnimatedMessageEntry(child: bubble) : bubble,
          );
        }

        final adjustedIndex = index - _optimisticMessages.length;

        // 2. Pending Image Uploads
        if (adjustedIndex < _pendingUploads.length) {
          final pendingItem = _pendingUploads[adjustedIndex];
          return KeyedSubtree(
            key: ValueKey('pending_${pendingItem.id}'),
            child: _buildPendingUploadBubble(pendingItem),
          );
        }

        // 3. Synced D1 Messages
        final docIndex = adjustedIndex - _pendingUploads.length;
        final msg = messages[docIndex];
        final msgId = (msg['id'] ?? msg['messageId'] ?? 'msg_$docIndex').toString();

        final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim().toLowerCase();
        final msgSenderHandle = (msg['senderHandle'] ?? '').toString().replaceAll('@', '').trim().toLowerCase();
        final isMe = msgSenderHandle.isNotEmpty && msgSenderHandle == cleanMe;

        final bubble = _buildMessageBubble(msg, msgId, isMe);

        final currentTimestamp = _parseTimestamp(msg['timestamp'] ?? msg['createdAt']);
        final showDateSeparator = docIndex == messages.length - 1 ||
            !_isSameDay(
              currentTimestamp,
              _parseTimestamp(
                messages[docIndex + 1]['timestamp'] ?? messages[docIndex + 1]['createdAt'],
              ),
            );

        final bool isNew = !_animatedMessageIds.contains(msgId);
        if (isNew) _animatedMessageIds.add(msgId);

        Widget itemWidget = bubble;
        if (showDateSeparator) {
          itemWidget = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              bubble,
              _buildDateSeparator(currentTimestamp),
            ],
          );
        }

        // Only animate NEW incoming or sent messages on first arrival, NEVER re-animate during polling
        if (isNew && index == 0) {
          itemWidget = _AnimatedMessageEntry(child: itemWidget);
        }

        return KeyedSubtree(
          key: ValueKey(showDateSeparator ? 'msg_sep_$msgId' : 'msg_$msgId'),
          child: itemWidget,
        );
      },
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(bool isDark) {
    return AppBar(
      key: const ValueKey('selection_app_bar'),
      backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
      elevation: 0.5,
      scrolledUnderElevation: 0.5,
      leading: IconButton(
        icon: Icon(
          Icons.close_rounded,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
        tooltip: 'Clear selection',
        onPressed: _clearSelection,
      ),
      title: Text(
        '${_selectedMessageIds.length} Selected',
        style: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF0F172A),
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      actions: [
        if (_canEditSelectedMessage())
          IconButton(
            icon: Icon(
              Icons.edit_outlined,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              size: 22,
            ),
            tooltip: 'Edit message',
            onPressed: _startEditingMessage,
          ),
        IconButton(
          icon: Icon(
            Icons.copy_rounded,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            size: 21,
          ),
          tooltip: 'Copy',
          onPressed: _copySelectedMessages,
        ),
        IconButton(
          icon: Transform.flip(
            flipX: true,
            child: Icon(
              Icons.reply_rounded,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              size: 22,
            ),
          ),
          tooltip: 'Forward',
          onPressed: _forwardSelectedMessages,
        ),
        IconButton(
          icon: const Icon(
            Icons.delete_outline_rounded,
            color: Color(0xFFEF4444),
            size: 22,
          ),
          tooltip: 'Delete',
          onPressed: _deleteSelectedMessages,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  PreferredSizeWidget _buildNormalAppBar(bool isDark) {
    return AppBar(
      key: const ValueKey('normal_app_bar'),
      backgroundColor: isDark ? Colors.black : Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_rounded,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
        onPressed: () {
          _fireMarkChatRead();
          Navigator.pop(context);
        },
      ),
      title: InkWell(
        onTap: () {
          showOtherUserProfileSheet(
            context,
            partnerHandle: widget.partnerHandle,
            currentUserHandle: widget.currentUserHandle,
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              Hero(
                tag: 'chat_avatar_${widget.partnerHandle.replaceAll('@', '').trim().toLowerCase()}',
                child: UserAvatar(
                  handle: widget.partnerHandle,
                  size: 38,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StreamBuilder<UserPresence>(
                  stream: _presenceStream,
                  initialData: PresenceService.instance.getCachedPresence(widget.partnerHandle),
                  builder: (context, snapshot) {
                    final cleanPartner = widget.partnerHandle.replaceAll('@', '').trim();
                    final presence = snapshot.data;
                    final statusText = PresenceService.formatLastSeen(presence);
                    final isOnline = presence?.isOnline == true;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '@$cleanPartner',
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            _PulsingOnlineDot(isOnline: isOnline),
                            Flexible(
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  color: isOnline ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                  fontSize: 11.5,
                                  fontWeight: isOnline ? FontWeight.w700 : FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: const [
        // Voice and Video call system hidden for now
        SizedBox(width: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_isSelectionMode && _editingMessageId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _fireMarkChatRead();
          return;
        }
        if (_isSelectionMode) {
          _clearSelection();
        } else if (_editingMessageId != null) {
          _cancelEditing();
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isSelectionMode
                ? _buildSelectionAppBar(isDark)
                : _buildNormalAppBar(isDark),
          ),
        ),
        body: Column(
          children: [
            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _messagesStream,
                initialData: DirectChatService.instance.getLastKnownMessages(_chatId).isNotEmpty
                    ? DirectChatService.instance.getLastKnownMessages(_chatId)
                    : null,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF2563EB)),
                    );
                  }

                  if (snapshot.hasError) {
                    debugPrint('Personal chat messages stream error: ${snapshot.error}');
                  }

                  final rawDocs = snapshot.data ?? [];
                  if (rawDocs.isEmpty && _optimisticMessages.isEmpty && _pendingUploads.isEmpty) {
                    return _buildEmptyChatPlaceholder();
                  }

                  final sortedDocs = List<Map<String, dynamic>>.from(rawDocs);
                  sortedDocs.sort((a, b) {
                    final aTime = _parseTimestamp(a['timestamp'] ?? a['createdAt']).millisecondsSinceEpoch;
                    final bTime = _parseTimestamp(b['timestamp'] ?? b['createdAt']).millisecondsSinceEpoch;
                    if (bTime != aTime) {
                      return bTime.compareTo(aTime);
                    }
                    final aId = (a['id'] ?? a['messageId'] ?? '').toString();
                    final bId = (b['id'] ?? b['messageId'] ?? '').toString();
                    return bId.compareTo(aId);
                  });

                  // 🚀 Instant 0ms Chat Image Prefetch
                  final List<String> chatImages = [];
                  for (final doc in sortedDocs.take(20)) {
                    final img = doc['imageUrl'] as String?;
                    if (img != null && img.isNotEmpty && !img.endsWith('.m4a') && !img.endsWith('.mp3')) {
                      chatImages.add(img);
                    }
                    final mediaUrls = doc['mediaUrls'] as List?;
                    if (mediaUrls != null) {
                      for (final m in mediaUrls) {
                        if (m is String && m.isNotEmpty && !chatImages.contains(m)) {
                          chatImages.add(m);
                        }
                      }
                    }
                  }
                  if (chatImages.isNotEmpty) {
                    AppImageCacheService.instance.prefetchImages(chatImages);
                  }

                  _hasMoreMessages = sortedDocs.length >= _messageLimit;
                  return _buildMessagesList(sortedDocs);
                },
              ),
            ),
            if (_isSendingVoice)
              LinearProgressIndicator(
                backgroundColor: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0),
                color: isDark ? Colors.white : Colors.black,
              ),

            // ── Edit Message Banner (200ms Slide Down + Fade) ───────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                final slideAnim = Tween<Offset>(
                  begin: const Offset(0.0, 0.5),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
                return SlideTransition(
                  position: slideAnim,
                  child: FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      sizeFactor: animation,
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  ),
                );
              },
              child: _editingMessageId != null
                  ? Container(
                      key: const ValueKey('active_edit_banner'),
                      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                        border: Border(
                          top: BorderSide(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFDBEAFE),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3.5,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.edit_rounded,
                            size: 18,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Edit message',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _editingOriginalContent ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            onPressed: _cancelEditing,
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('empty_edit_banner')),
            ),

            // ── Reply Banner ────────────────────────────────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: _replyingTo != null && _editingMessageId == null
                  ? ReplyPreviewBanner(
                      senderHandle:
                          (_replyingTo!['senderHandle'] ?? '') as String,
                      previewText:
                          (_replyingTo!['previewText'] ?? '') as String,
                      isMe: _replyingTo!['isMe'] == true,
                      onCancel: () => setState(() => _replyingTo = null),
                    )
                  : const SizedBox.shrink(),
            ),

            // ── Input Bar (normal or recording) ────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.black : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? const Color(0xFF262626)
                        : const Color(0xFFF1F5F9),
                    width: 1,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: _isRecording
                    // ── Recording State Bar ──────────────────────────────────
                    ? Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: Row(
                          children: [
                            // Animated red dot
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.3, end: 1.0),
                              duration: const Duration(milliseconds: 600),
                              builder: (_, val, c) => Opacity(
                                opacity: val,
                                child: const Icon(
                                  Icons.circle,
                                  color: Color(0xFFEF4444),
                                  size: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ValueListenableBuilder<int>(
                              valueListenable: _recordingSecondsNotifier,
                              builder: (context, seconds, _) {
                                return Text(
                                  'REC  ${_formatRecordingTime(seconds)}',
                                  style: const TextStyle(
                                    color: Color(0xFFEF4444),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    letterSpacing: 0.5,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 10),
                            // Mini waveform preview
                            Expanded(
                              child: SizedBox(
                                height: 28,
                                child: ValueListenableBuilder<List<double>>(
                                  valueListenable: _recordingAmplitudesNotifier,
                                  builder: (context, amplitudes, _) {
                                    return Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: List.generate(
                                        20,
                                        (i) {
                                          final idx = (amplitudes.length - 20 + i)
                                              .clamp(0, amplitudes.length - 1);
                                          final h = amplitudes.isEmpty
                                              ? 0.2
                                              : amplitudes[idx];
                                          return AnimatedContainer(
                                            duration:
                                                const Duration(milliseconds: 80),
                                            width: 3,
                                            height: (28 * h).clamp(4.0, 28.0),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEF4444)
                                                  .withValues(alpha: 0.7),
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Cancel
                            GestureDetector(
                              onTap: _stopAndCancelRecording,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF262626)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF374151),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Send recording
                            GestureDetector(
                              onTap: _stopAndSendVoiceNote,
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 19,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    // ── Normal Input Bar ─────────────────────────────────────
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 12, 12),
                        child: Row(
                          children: [
                            AnimatedRotation(
                              turns: _isMediaPickerOpen ? 0.125 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              child: IconButton(
                                icon: Icon(
                                  Icons.add_photo_alternate_rounded,
                                  color: isDark
                                      ? const Color(0xFF9A9A9A)
                                      : const Color(0xFF6E6E6E),
                                  size: 24,
                                ),
                                onPressed: _editingMessageId != null ? null : _pickAndSendImages,
                                tooltip: 'Attach Media',
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                focusNode: _focusNode,
                                controller: _messageController,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _editingMessageId != null
                                    ? _saveEditedMessage()
                                    : _sendMessage(),
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                  fontSize: 14.5,
                                ),
                                decoration: InputDecoration(
                                  hintText: _editingMessageId != null
                                      ? 'Edit message...'
                                      : (_replyingTo != null
                                          ? (_replyingTo!['isMe'] == true
                                              ? 'Reply to yourself...'
                                              : 'Reply to @${(_replyingTo!['senderHandle'] ?? '').toString().replaceAll('@', '')}...')
                                          : 'Type a message...'),
                                  hintStyle: TextStyle(
                                    color: isDark
                                        ? const Color(0xFF6E6E6E)
                                        : const Color(0xFF94A3B8),
                                    fontSize: 14,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? const Color(0xFF141414)
                                      : const Color(0xFFF8FAFC),
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Send button OR mic button / save button
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _messageController,
                              builder: (context, textVal, _) {
                                final hasText = textVal.text.trim().isNotEmpty;
                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(scale: anim, child: child),
                                  child: _editingMessageId != null
                                      ? Container(
                                          key: const ValueKey('save_edit'),
                                          width: 42,
                                          height: 42,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF2563EB),
                                            shape: BoxShape.circle,
                                          ),
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.check_rounded,
                                              color: Colors.white,
                                              size: 21,
                                            ),
                                            onPressed: _saveEditedMessage,
                                          ),
                                        )
                                      : (hasText
                                          ? Container(
                                              key: const ValueKey('send'),
                                              width: 42,
                                              height: 42,
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black,
                                                shape: BoxShape.circle,
                                              ),
                                              child: IconButton(
                                                icon: Icon(
                                                  Icons.send_rounded,
                                                  color: isDark
                                                      ? Colors.black
                                                      : Colors.white,
                                                  size: 19,
                                                ),
                                                onPressed: _sendMessage,
                                              ),
                                            )
                                          : GestureDetector(
                                              key: const ValueKey('mic'),
                                              onLongPressStart: (_) =>
                                                  _startRecording(),
                                              onLongPressEnd: (_) =>
                                                  _stopAndSendVoiceNote(),
                                              onTap: _startRecording,
                                              child: Container(
                                                width: 42,
                                                height: 42,
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons.mic_rounded,
                                                  color: isDark
                                                      ? Colors.black
                                                      : Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                            )),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForwardedLabel(bool isMe, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shortcut_rounded,
            size: 13,
            color: isMe
                ? (isDark ? Colors.black45 : Colors.white60)
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
          ),
          const SizedBox(width: 4),
          Text(
            'Forwarded',
            style: TextStyle(
              color: isMe
                  ? (isDark ? Colors.black45 : Colors.white70)
                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              fontSize: 11,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ForwardMessageSheet extends StatefulWidget {
  final List<Map<String, dynamic>> messagesToForward;
  final String currentUserHandle;

  const _ForwardMessageSheet({
    required this.messagesToForward,
    required this.currentUserHandle,
  });

  @override
  State<_ForwardMessageSheet> createState() => _ForwardMessageSheetState();
}

class _ForwardMessageSheetState extends State<_ForwardMessageSheet> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedHandles = {};
  List<String> _chatPartners = [];
  bool _isLoading = true;
  bool _isForwarding = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadPartners();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPartners() async {
    final cleanHandle = widget.currentUserHandle.replaceAll('@', '').trim();
    try {
      final partners = <String>{};

      // 1. Load from recent chats
      final chats = await DirectChatService.instance.getChats(cleanHandle);
      for (final conv in chats) {
        final partner = conv.getPartnerHandle(cleanHandle).replaceAll('@', '').trim();
        if (partner.isNotEmpty && partner.toLowerCase() != cleanHandle.toLowerCase()) {
          partners.add(partner);
        }
      }

      // 2. Load from friends
      try {
        final repo = FriendRepository()..currentUserHandle = widget.currentUserHandle;
        final friends = await repo.fetchFriends();
        for (final f in friends) {
          final partner = f.getOtherUser(cleanHandle).replaceAll('@', '').trim();
          if (partner.isNotEmpty && partner.toLowerCase() != cleanHandle.toLowerCase()) {
            partners.add(partner);
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _chatPartners = partners.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading forward partners: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forwardToSelected() async {
    if (_selectedHandles.isEmpty || _isForwarding || widget.messagesToForward.isEmpty) return;
    setState(() => _isForwarding = true);

    final cleanMe = widget.currentUserHandle.replaceAll('@', '').trim();
    int successCount = 0;

    for (final target in _selectedHandles) {
      final cleanTarget = target.replaceAll('@', '').trim();
      final targetChatId = DirectChatService.getChatId(cleanMe, cleanTarget);

      try {
        for (final msg in widget.messagesToForward) {
          final forwardType = (msg['type'] ?? 'text') as String;
          final content = (msg['content'] ?? '') as String;
          final imageUrl = msg['imageUrl'] as String?;
          final rawMediaUrls = msg['mediaUrls'];
          final List<String>? mediaUrls = rawMediaUrls is List ? rawMediaUrls.map((e) => e.toString()).toList() : null;

          String summary = content;
          if (summary.isEmpty) {
            if (forwardType == 'voice_note') {
              summary = '🎙️ Voice note';
            } else if (forwardType == 'image' || forwardType == 'image_group') {
              summary = '📷 Photo';
            } else {
              summary = 'Forwarded message';
            }
          }

          final res = await DirectChatService.instance.sendMessage(
            sender: cleanMe,
            receiver: cleanTarget,
            content: content,
            imageUrl: imageUrl,
            mediaUrls: mediaUrls,
            messageType: forwardType,
          );

          if (res != null && res['success'] == true) {
            NotificationService().sendNotification(
              targetHandle: cleanTarget,
              title: '@$cleanMe',
              body: summary,
              data: {
                'type': 'chat',
                'senderHandle': cleanMe,
                'partnerHandle': cleanMe,
                'chatId': targetChatId,
              },
            );
          }
        }
        successCount++;
      } catch (e) {
        debugPrint('Forward error to @$cleanTarget: $e');
      }
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Forwarded to $successCount chat${successCount > 1 ? 's' : ''}'),
          backgroundColor: const Color(0xFF16A34A),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredPartners = _chatPartners.where((handle) {
      if (_searchQuery.isEmpty) return true;
      return handle.toLowerCase().contains(_searchQuery);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Forward to...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                if (_selectedHandles.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedHandles.length} selected',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search friends or recent chats...',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          // List of Partners
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredPartners.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty ? 'No recent chats found' : 'No matches found',
                          style: TextStyle(
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredPartners.length,
                        itemBuilder: (context, index) {
                          final handle = filteredPartners[index];
                          final isSelected = _selectedHandles.contains(handle);

                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedHandles.remove(handle);
                                } else {
                                  _selectedHandles.add(handle);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  UserAvatar(handle: handle, size: 44, fontSize: 16),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      handle.displayHandle,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? const Color(0xFF2563EB)
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF2563EB)
                                            : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                                        width: 2,
                                      ),
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          // Bottom Forward Button
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _selectedHandles.isNotEmpty && !_isForwarding
                      ? _forwardToSelected
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFE2E8F0),
                    disabledForegroundColor: isDark
                        ? const Color(0xFF475569)
                        : const Color(0xFF94A3B8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _isForwarding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    _selectedHandles.isEmpty
                        ? 'Select chats to forward'
                        : 'Forward to ${_selectedHandles.length} chat${_selectedHandles.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingOnlineDot extends StatefulWidget {
  final bool isOnline;
  const _PulsingOnlineDot({required this.isOnline});

  @override
  State<_PulsingOnlineDot> createState() => _PulsingOnlineDotState();
}

class _PulsingOnlineDotState extends State<_PulsingOnlineDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isOnline) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _PulsingOnlineDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOnline != oldWidget.isOnline) {
      if (widget.isOnline) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isOnline) {
      return ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(right: 5),
          decoration: const BoxDecoration(
            color: Color(0xFF16A34A),
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.only(right: 5),
      decoration: const BoxDecoration(
        color: Color(0xFF94A3B8),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _AnimatedMessageEntry extends StatefulWidget {
  final Widget child;

  const _AnimatedMessageEntry({
    required this.child,
  });

  @override
  State<_AnimatedMessageEntry> createState() => _AnimatedMessageEntryState();
}

class _AnimatedMessageEntryState extends State<_AnimatedMessageEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}



