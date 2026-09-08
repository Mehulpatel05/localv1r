import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/community_model.dart';

class CommunityRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String currentUserHandle = '';

  String get currentUserHandle => _currentUserHandle;
  set currentUserHandle(String handle) => _currentUserHandle = handle;

  // Bug #6 fixed: N+1 query eliminated using whereIn batch
  Stream<List<CommunityModel>> getUserCommunities() {
    return _db
        .collection('community_members')
        .where('userHandle', isEqualTo: _currentUserHandle)
        .snapshots()
        .asyncMap((snapshot) async {
      if (snapshot.docs.isEmpty) return [];
      final ids = snapshot.docs
          .map((d) => d.data()['communityId'] as String)
          .toList();

      // Firestore whereIn limit is 30; chunk if needed
      final List<CommunityModel> communities = [];
      const chunkSize = 30;
      for (var i = 0; i < ids.length; i += chunkSize) {
        final chunk = ids.sublist(
            i, i + chunkSize > ids.length ? ids.length : i + chunkSize);
        final qs = await _db
            .collection('communities')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        communities.addAll(
          qs.docs.map((d) => CommunityModel.fromMap(d.data(), d.id)),
        );
      }
      // Sort by name for consistent ordering
      communities.sort((a, b) => a.name.compareTo(b.name));
      return communities;
    });
  }

  // Bug #4 fixed: Returns only communities the user has NOT joined
  Stream<List<CommunityModel>> getDiscoverCommunities() {
    return _db
        .collection('community_members')
        .where('userHandle', isEqualTo: _currentUserHandle)
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

  // Get all public communities (kept for backward compat)
  Stream<List<CommunityModel>> getAllCommunities() {
    return _db
        .collection('communities')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => CommunityModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  // Feature #13: Get unread message count for a community
  // Tracks last-read timestamp per user per community in community_members doc
  Future<int> getUnreadCount(String communityId) async {
    final memberDoc = await _db
        .collection('community_members')
        .doc('${communityId}_$_currentUserHandle')
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
  }

  // Feature #13: Mark community as read (update lastReadAt)
  Future<void> markAsRead(String communityId) async {
    final memberId = '${communityId}_$_currentUserHandle';
    await _db.collection('community_members').doc(memberId).update({
      'lastReadAt': FieldValue.serverTimestamp(),
    });
  }

  // Get messages for a specific community
  Stream<List<CommunityMessage>> getCommunityMessages(String communityId,
      {int limit = 30}) {
    return _db
        .collection('community_messages')
        .where('communityId', isEqualTo: communityId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => CommunityMessage.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  // Create a new community
  Future<void> createCommunity({
    required String name,
    required String description,
    required bool isChannel,
  }) async {
    final docRef = await _db.collection('communities').add({
      'name': name,
      'description': description,
      'isChannel': isChannel,
      'adminHandle': _currentUserHandle,
      'adminUid': FirebaseAuth.instance.currentUser?.uid,
      'memberCount': 1,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Auto-join the creator
    await _db
        .collection('community_members')
        .doc('${docRef.id}_$_currentUserHandle')
        .set({
      'userHandle': _currentUserHandle,
      'userUid': FirebaseAuth.instance.currentUser?.uid,
      'communityId': docRef.id,
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
      'lastReadAt': FieldValue.serverTimestamp(),
    });
  }

  // Join a community
  Future<void> joinCommunity(String communityId) async {
    final memberId = '${communityId}_$_currentUserHandle';
    final docRef = _db.collection('community_members').doc(memberId);
    final doc = await docRef.get();
    if (doc.exists) return; // already a member

    await docRef.set({
      'communityId': communityId,
      'userHandle': _currentUserHandle,
      'userUid': FirebaseAuth.instance.currentUser?.uid,
      'joinedAt': FieldValue.serverTimestamp(),
      'lastReadAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('communities').doc(communityId).update({
      'memberCount': FieldValue.increment(1),
    });
  }

  Future<void> leaveCommunity(String communityId) async {
    final memberId = '${communityId}_$_currentUserHandle';
    await _db.collection('community_members').doc(memberId).delete();

    await _db.collection('communities').doc(communityId).update({
      'memberCount': FieldValue.increment(-1),
    });
  }

  // Bug #3 fixed: deleteCommunity now also deletes all members and messages
  Future<void> deleteCommunity(String communityId) async {
    final doc =
        await _db.collection('communities').doc(communityId).get();
    if (!doc.exists || doc.data()?['adminHandle'] != _currentUserHandle) {
      throw Exception('Only the admin can delete this community.');
    }

    final batch = _db.batch();

    // Delete all member records
    final membersSnap = await _db
        .collection('community_members')
        .where('communityId', isEqualTo: communityId)
        .get();
    for (final m in membersSnap.docs) {
      batch.delete(m.reference);
    }

    // Delete all messages
    final messagesSnap = await _db
        .collection('community_messages')
        .where('communityId', isEqualTo: communityId)
        .get();
    for (final m in messagesSnap.docs) {
      batch.delete(m.reference);
    }

    // Delete the community document itself
    batch.delete(_db.collection('communities').doc(communityId));

    await batch.commit();
  }

  Future<bool> isMember(String communityId) async {
    final memberRef = _db
        .collection('community_members')
        .doc('${communityId}_$_currentUserHandle');
    final doc = await memberRef.get();
    return doc.exists;
  }

  // Get all members of a community (Feature #10)
  Stream<List<Map<String, dynamic>>> getCommunityMembers(String communityId) {
    return _db
        .collection('community_members')
        .where('communityId', isEqualTo: communityId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // Admin remove a member (Feature #14)
  Future<void> removeMember(String communityId, String memberHandle) async {
    // Verify caller is admin
    final communityDoc =
        await _db.collection('communities').doc(communityId).get();
    if (communityDoc.data()?['adminHandle'] != _currentUserHandle) {
      throw Exception('Only admins can remove members.');
    }
    if (memberHandle == _currentUserHandle) {
      throw Exception('Admin cannot remove themselves. Delete the community instead.');
    }

    final memberId = '${communityId}_$memberHandle';
    await _db.collection('community_members').doc(memberId).delete();
    await _db.collection('communities').doc(communityId).update({
      'memberCount': FieldValue.increment(-1),
    });
  }

  // Send a message
  Future<void> sendMessage(String communityId, String content) async {
    final isMem = await isMember(communityId);
    if (!isMem) throw Exception('Must be a member to post.');

    if (content.trim().isEmpty) return;
    await _db.collection('community_messages').add({
      'communityId': communityId,
      'authorHandle': _currentUserHandle,
      'authorUid': FirebaseAuth.instance.currentUser?.uid,
      'content': content.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}