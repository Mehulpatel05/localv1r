import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/community_model.dart';

class CommunityRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _currentUserHandle = '';

  String get currentUserHandle => _currentUserHandle;
  set currentUserHandle(String handle) => _currentUserHandle = handle;

  // Get all communities the current user is a member of
  Stream<List<CommunityModel>> getUserCommunities() {
    return _db
        .collection('community_members')
        .where('userHandle', isEqualTo: _currentUserHandle)
        .snapshots()
        .asyncMap((snapshot) async {
      List<CommunityModel> communities = [];
      for (var doc in snapshot.docs) {
        final communityId = doc.data()['communityId'] as String;
        final cDoc = await _db.collection('communities').doc(communityId).get();
        if (cDoc.exists) {
          communities.add(CommunityModel.fromMap(cDoc.data()!, cDoc.id));
        }
      }
      return communities;
    });
  }

  // Get all public communities (Discover)
  Stream<List<CommunityModel>> getAllCommunities() {
    return _db.collection('communities').orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => CommunityModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Get messages for a specific community
  Stream<List<CommunityMessage>> getCommunityMessages(String communityId, {int limit = 30}) {
    return _db
        .collection('community_messages')
        .where('communityId', isEqualTo: communityId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => CommunityMessage.fromMap(doc.data(), doc.id)).toList();
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
    await _db.collection('community_members').doc('${docRef.id}_$_currentUserHandle').set({
      'userHandle': _currentUserHandle,
      'userUid': FirebaseAuth.instance.currentUser?.uid,
      'communityId': docRef.id,
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
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

  Future<void> deleteCommunity(String communityId) async {
    // Note: In a real app, you'd also delete all members and messages in a batch/function.
    // Here we'll delete the community document itself.
    final doc = await _db.collection('communities').doc(communityId).get();
    if (doc.exists && doc.data()?['adminHandle'] == _currentUserHandle) {
      await _db.collection('communities').doc(communityId).delete();
    } else {
      throw Exception('Only the admin can delete the community.');
    }
  }
  
  Future<bool> isMember(String communityId) async {
    final memberRef = _db.collection('community_members').doc('${communityId}_$_currentUserHandle');
    final doc = await memberRef.get();
    return doc.exists;
  }

  // Send a message
  Future<void> sendMessage(String communityId, String content) async {
    final isMem = await isMember(communityId);
    if (!isMem) throw Exception("Must be a member to post.");

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
