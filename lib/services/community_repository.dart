import 'package:cloud_firestore/cloud_firestore.dart';
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
  Stream<List<CommunityMessage>> getCommunityMessages(String communityId) {
    return _db
        .collection('community_messages')
        .where('communityId', isEqualTo: communityId)
        .orderBy('timestamp', descending: true)
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
      'memberCount': 1,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Auto-join the creator
    await _db.collection('community_members').doc('${_currentUserHandle}_${docRef.id}').set({
      'userHandle': _currentUserHandle,
      'communityId': docRef.id,
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

  // Join a community
  Future<void> joinCommunity(String communityId) async {
    final memberRef = _db.collection('community_members').doc('${_currentUserHandle}_$communityId');
    final doc = await memberRef.get();
    if (!doc.exists) {
      await memberRef.set({
        'userHandle': _currentUserHandle,
        'communityId': communityId,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      });
      // Increment member count
      await _db.collection('communities').doc(communityId).update({
        'memberCount': FieldValue.increment(1),
      });
    }
  }
  
  Future<bool> isMember(String communityId) async {
    final memberRef = _db.collection('community_members').doc('${_currentUserHandle}_$communityId');
    final doc = await memberRef.get();
    return doc.exists;
  }

  // Send a message
  Future<void> sendMessage(String communityId, String content) async {
    if (content.trim().isEmpty) return;
    await _db.collection('community_messages').add({
      'communityId': communityId,
      'authorHandle': _currentUserHandle,
      'content': content.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
