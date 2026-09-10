import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/community_model.dart';
import 'telegram_storage_service.dart';

class CommunityRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String currentUserHandle = '';

  // Bug #6 fixed: N+1 query eliminated using whereIn batch
  Stream<List<CommunityModel>> getUserCommunities() {
    return _db
        .collection('community_members')
        .where('userHandle', isEqualTo: currentUserHandle)
        .snapshots()
        .asyncMap((snapshot) async {
      if (snapshot.docs.isEmpty) return [];
      final ids = snapshot.docs
          .map((d) => d.data()['communityId'] as String)
          .toList();

      final List<CommunityModel> communities = [];
      const chunkSize = 30;
      for (var i = 0; i < ids.length; i += chunkSize) {
        final chunk = ids.sublist(
            i, i + chunkSize > ids.length ? ids.length : i + chunkSize);
        final qs = await _db
            .collection('communities')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        communities
            .addAll(qs.docs.map((d) => CommunityModel.fromMap(d.data(), d.id)));
      }
      communities.sort((a, b) => a.name.compareTo(b.name));
      return communities;
    });
  }

  // Bug #4 fixed: Returns only communities the user has NOT joined
  Stream<List<CommunityModel>> getDiscoverCommunities() {
    return _db
        .collection('community_members')
        .where('userHandle', isEqualTo: currentUserHandle)
        .snapshots()
        .asyncMap((memberSnap) async {
      final joinedIds = memberSnap.docs
          .map((d) => d.data()['communityId'] as String)
          .toSet();

      final allSnap = await _db
          .collection('communities')
          .orderBy('createdAt', descending: true)
          .get();

      return allSnap.docs
          .where((d) => !joinedIds.contains(d.id))
          .map((d) => CommunityModel.fromMap(d.data(), d.id))
          .toList();
    });
  }


  // Feature #13: Get unread message count
  Future<int> getUnreadCount(String communityId) async {
    try {
      final memberDoc = await _db
          .collection('community_members')
          .doc('${communityId}_$currentUserHandle')
          .get();

      DateTime lastRead = DateTime.fromMillisecondsSinceEpoch(0);
      if (memberDoc.exists && memberDoc.data()?['lastReadAt'] != null) {
        lastRead = (memberDoc.data()!['lastReadAt'] as Timestamp).toDate();
      }

      final unread = await _db
          .collection('community_messages')
          .where('communityId', isEqualTo: communityId)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(lastRead))
          .get();

      return unread.docs.length;
    } catch (_) {
      return 0;
    }
  }

  // Feature #13: Mark community as read (safe merge so it never throws if doc is missing)
  Future<void> markAsRead(String communityId) async {
    try {
      final memberId = '${communityId}_$currentUserHandle';
      await _db.collection('community_members').doc(memberId).set({
        'lastReadAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Stream<List<CommunityMessage>> getCommunityMessages(String communityId,
      {int limit = 30}) {
    return _db
        .collection('community_messages')
        .where('communityId', isEqualTo: communityId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CommunityMessage.fromMap(doc.data(), doc.id))
            .toList());
  }

  // Feature #7: Create community with optional avatar image
  Future<void> createCommunity({
    required String name,
    required String description,
    required bool isChannel,
    File? imageFile,
  }) async {
    String? imageUrl;
    if (imageFile != null) {
      imageUrl = await TelegramStorageService.uploadImage(imageFile);
    }

    final docRef = await _db.collection('communities').add({
      'name': name,
      'description': description,
      'isChannel': isChannel,
      'adminHandle': currentUserHandle,
      'adminUid': FirebaseAuth.instance.currentUser?.uid,
      'memberCount': 1,
      'createdAt': FieldValue.serverTimestamp(),
      // ignore: use_null_aware_elements
      if (imageUrl != null) 'imageUrl': imageUrl,
    });

    await _db
        .collection('community_members')
        .doc('${docRef.id}_$currentUserHandle')
        .set({
      'userHandle': currentUserHandle,
      'userUid': FirebaseAuth.instance.currentUser?.uid,
      'communityId': docRef.id,
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
      'lastReadAt': FieldValue.serverTimestamp(),
    });
  }

  // Feature #7: Update community avatar (kept for direct use)
  Future<void> updateCommunityImage(String communityId, File imageFile) async {
    final imageUrl = await TelegramStorageService.uploadImage(imageFile);
    if (imageUrl == null) throw Exception('Image upload failed.');
    await _db.collection('communities').doc(communityId).update({
      'imageUrl': imageUrl,
    });
  }

  // F2: Edit community name, description, and optionally avatar (admin only)
  Future<void> editCommunity({
    required String communityId,
    required String name,
    required String description,
    File? imageFile,
  }) async {
    final doc = await _db.collection('communities').doc(communityId).get();
    if (!doc.exists || doc.data()?['adminHandle'] != currentUserHandle) {
      throw Exception('Only the admin can edit this community.');
    }

    final updates = <String, dynamic>{
      'name': name,
      'description': description,
    };

    if (imageFile != null) {
      final imageUrl = await TelegramStorageService.uploadImage(imageFile);
      if (imageUrl == null) throw Exception('Image upload failed.');
      updates['imageUrl'] = imageUrl;
    }

    await _db.collection('communities').doc(communityId).update(updates);
  }

  Future<void> joinCommunity(String communityId) async {
    final memberId = '${communityId}_$currentUserHandle';
    final docRef = _db.collection('community_members').doc(memberId);
    final doc = await docRef.get();
    if (doc.exists) return;

    await docRef.set({
      'communityId': communityId,
      'userHandle': currentUserHandle,
      'userUid': FirebaseAuth.instance.currentUser?.uid,
      'joinedAt': FieldValue.serverTimestamp(),
      'lastReadAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('communities').doc(communityId).update({
      'memberCount': FieldValue.increment(1),
    });
  }

  Future<void> leaveCommunity(String communityId) async {
    final memberId = '${communityId}_$currentUserHandle';
    await _db.collection('community_members').doc(memberId).delete();
    await _db.collection('communities').doc(communityId).update({
      'memberCount': FieldValue.increment(-1),
    });
  }

  // B2 fixed: chunked batch delete — Firestore limit is 500 ops per batch
  // Splits members + messages into chunks of 499, commits each separately
  Future<void> deleteCommunity(String communityId) async {
    final doc = await _db.collection('communities').doc(communityId).get();
    if (!doc.exists || doc.data()?['adminHandle'] != currentUserHandle) {
      throw Exception('Only the admin can delete this community.');
    }

    // Collect all refs to delete
    final refs = <DocumentReference>[];

    final membersSnap = await _db
        .collection('community_members')
        .where('communityId', isEqualTo: communityId)
        .get();
    refs.addAll(membersSnap.docs.map((d) => d.reference));

    final messagesSnap = await _db
        .collection('community_messages')
        .where('communityId', isEqualTo: communityId)
        .get();
    refs.addAll(messagesSnap.docs.map((d) => d.reference));

    // Add the community doc itself at the end
    refs.add(_db.collection('communities').doc(communityId));

    // Commit in chunks of 499 (leaving 1 slot buffer for safety)
    const chunkSize = 499;
    for (var i = 0; i < refs.length; i += chunkSize) {
      final chunk = refs.sublist(
          i, i + chunkSize > refs.length ? refs.length : i + chunkSize);
      final batch = _db.batch();
      for (final ref in chunk) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  // B5: Fetch a single community by ID — used to refresh AppBar after edit
  Future<CommunityModel?> getCommunityById(String communityId) async {
    final doc = await _db.collection('communities').doc(communityId).get();
    if (!doc.exists) return null;
    return CommunityModel.fromMap(doc.data()!, doc.id);
  }

  Future<bool> isMember(String communityId) async {
    try {
      final doc = await _db
          .collection('community_members')
          .doc('${communityId}_$currentUserHandle')
          .get();
      if (doc.exists) return true;

      // Fallback: check if current user is the admin/creator of this community
      final commDoc = await _db.collection('communities').doc(communityId).get();
      if (commDoc.exists && commDoc.data()?['adminHandle'] == currentUserHandle) {
        // Auto-heal missing member doc
        await _db
            .collection('community_members')
            .doc('${communityId}_$currentUserHandle')
            .set({
          'userHandle': currentUserHandle,
          'userUid': FirebaseAuth.instance.currentUser?.uid,
          'communityId': communityId,
          'role': 'admin',
          'joinedAt': FieldValue.serverTimestamp(),
          'lastReadAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // Feature #10: Get all members of a community
  Stream<List<Map<String, dynamic>>> getCommunityMembers(String communityId) {
    return _db
        .collection('community_members')
        .where('communityId', isEqualTo: communityId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // F5: Transfer admin role to another member
  Future<void> transferAdmin(String communityId, String newAdminHandle) async {
    final communityDoc = await _db.collection('communities').doc(communityId).get();
    if (communityDoc.data()?['adminHandle'] != currentUserHandle) {
      throw Exception('Only the current admin can transfer admin rights.');
    }
    if (newAdminHandle == currentUserHandle) return;

    final batch = _db.batch();

    // Update old admin role -> member
    final oldAdminRef = _db
        .collection('community_members')
        .doc('${communityId}_$currentUserHandle');
    batch.update(oldAdminRef, {'role': 'member'});

    // Update new admin role -> admin
    final newAdminRef = _db
        .collection('community_members')
        .doc('${communityId}_$newAdminHandle');
    batch.update(newAdminRef, {'role': 'admin'});

    // Update community doc
    batch.update(_db.collection('communities').doc(communityId), {
      'adminHandle': newAdminHandle,
    });

    await batch.commit();
  }

  // Feature #14: Admin removes a member
  Future<void> removeMember(String communityId, String memberHandle) async {
    final communityDoc =
        await _db.collection('communities').doc(communityId).get();
    if (communityDoc.data()?['adminHandle'] != currentUserHandle) {
      throw Exception('Only admins can remove members.');
    }
    if (memberHandle == currentUserHandle) {
      throw Exception(
          'Admin cannot remove themselves. Delete the community instead.');
    }

    final memberId = '${communityId}_$memberHandle';
    await _db.collection('community_members').doc(memberId).delete();
    await _db.collection('communities').doc(communityId).update({
      'memberCount': FieldValue.increment(-1),
    });
  }

  // Send a text message
  Future<void> sendMessage(String communityId, String content) async {
    final isMem = await isMember(communityId);
    if (!isMem) throw Exception('Must be a member to post.');
    if (content.trim().isEmpty) return;

    await _db.collection('community_messages').add({
      'communityId': communityId,
      'authorHandle': currentUserHandle,
      'authorUid': FirebaseAuth.instance.currentUser?.uid,
      'content': content.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Feature #11: Send an image message via existing Telegram CDN
  Future<void> sendImageMessage(String communityId, File imageFile,
      {String caption = ''}) async {
    final isMem = await isMember(communityId);
    if (!isMem) throw Exception('Must be a member to post.');

    final imageUrl = await TelegramStorageService.uploadImage(imageFile);
    if (imageUrl == null) throw Exception('Image upload failed.');

    await _db.collection('community_messages').add({
      'communityId': communityId,
      'authorHandle': currentUserHandle,
      'authorUid': FirebaseAuth.instance.currentUser?.uid,
      'content': caption,
      'imageUrl': imageUrl,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Feature #9: Toggle emoji reaction — uses Firestore transaction to fix race condition (B1)
  // Without transaction: two users reacting simultaneously can overwrite each other's data
  Future<void> toggleReaction(String messageId, String emoji) async {
    final msgRef = _db.collection('community_messages').doc(messageId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(msgRef);
      if (!snapshot.exists) return;

      final reactions =
          Map<String, dynamic>.from(snapshot.data()?['reactions'] ?? {});
      final handles = List<String>.from(reactions[emoji] ?? []);

      if (handles.contains(currentUserHandle)) {
        handles.remove(currentUserHandle);
      } else {
        handles.add(currentUserHandle);
      }

      if (handles.isEmpty) {
        reactions.remove(emoji);
      } else {
        reactions[emoji] = handles;
      }

      transaction.update(msgRef, {'reactions': reactions});
    });
  }
}