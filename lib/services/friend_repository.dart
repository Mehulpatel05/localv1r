import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/friend_request_model.dart';
import '../models/friendship_model.dart';
import '../models/block_model.dart';

enum RelationshipStatus {
  none,
  requestSentByMe,
  requestReceivedByMe,
  friends,
  blockedByMe,
  blockedByThem,
}

class FriendRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _currentUserHandle = '';

  String get currentUserHandle => _currentUserHandle;
  set currentUserHandle(String handle) => _currentUserHandle = handle;

  // ── Helper: Deterministic friendship ID ──
  String _friendshipId(String a, String b) {
    final sorted = [a, b]..sort();
    return sorted.join('_');
  }

  // ── Check relationship status with another user ──
  Future<RelationshipStatus> getRelationshipStatus(String otherHandle) async {
    // Check if blocked by me
    final blockByMe = await _db.collection('blocks')
        .doc('${_currentUserHandle}_$otherHandle').get();
    if (blockByMe.exists) return RelationshipStatus.blockedByMe;

    // Check if blocked by them
    final blockByThem = await _db.collection('blocks')
        .doc('${otherHandle}_$_currentUserHandle').get();
    if (blockByThem.exists) return RelationshipStatus.blockedByThem;

    // Check if friends
    final friendshipDoc = await _db.collection('friendships')
        .doc(_friendshipId(_currentUserHandle, otherHandle)).get();
    if (friendshipDoc.exists) return RelationshipStatus.friends;

    // Check if I sent a request
    final sentRequest = await _db.collection('friend_requests')
        .doc('${_currentUserHandle}_$otherHandle').get();
    if (sentRequest.exists && sentRequest.data()?['status'] == 'pending') {
      return RelationshipStatus.requestSentByMe;
    }

    // Check if they sent me a request
    final receivedRequest = await _db.collection('friend_requests')
        .doc('${otherHandle}_$_currentUserHandle').get();
    if (receivedRequest.exists && receivedRequest.data()?['status'] == 'pending') {
      return RelationshipStatus.requestReceivedByMe;
    }

    return RelationshipStatus.none;
  }

  // ── Send Friend Request ──
  Future<void> sendFriendRequest(String receiverHandle) async {
    if (receiverHandle == _currentUserHandle) throw Exception('Cannot friend yourself');

    final status = await getRelationshipStatus(receiverHandle);
    if (status != RelationshipStatus.none) {
      throw Exception('Cannot send request: relationship already exists');
    }

    // Fetch receiverUid from profiles
    final profileDoc = await _db.collection('profiles').doc(receiverHandle).get();
    if (!profileDoc.exists) {
      throw Exception('User not found.');
    }
    final receiverUid = profileDoc.data()?['ownerUid'];
    if (receiverUid == null) {
      throw Exception('User profile is incomplete.');
    }

    final senderUid = FirebaseAuth.instance.currentUser?.uid;
    if (senderUid == null) throw Exception('Not authenticated.');

    final docId = '${_currentUserHandle}_$receiverHandle';
    await _db.collection('friend_requests').doc(docId).set({
      'senderHandle': _currentUserHandle,
      'senderUid': senderUid,
      'receiverHandle': receiverHandle,
      'receiverUid': receiverUid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Accept Friend Request ──
  Future<void> acceptFriendRequest(String senderHandle) async {
    final requestDocId = '${senderHandle}_$_currentUserHandle';
    final friendshipDocId = _friendshipId(senderHandle, _currentUserHandle);

    try {
      await _db.runTransaction((transaction) async {
        final requestRef = _db.collection('friend_requests').doc(requestDocId);
        final doc = await transaction.get(requestRef);
        
        if (!doc.exists) {
          throw Exception('Friend request no longer exists.');
        }
        if (doc.data()?['status'] != 'pending') {
          throw Exception('Friend request is already processed.');
        }

        // Update request status
        transaction.update(requestRef, {
          'status': 'accepted',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Create friendship
        final friendshipRef = _db.collection('friendships').doc(friendshipDocId);
        transaction.set(friendshipRef, {
          'users': [senderHandle, _currentUserHandle],
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Update friend counts atomically
        final senderProfileRef = _db.collection('profiles').doc(senderHandle);
        final currentProfileRef = _db.collection('profiles').doc(_currentUserHandle);
        
        transaction.update(senderProfileRef, {'friendCount': FieldValue.increment(1)});
        transaction.update(currentProfileRef, {'friendCount': FieldValue.increment(1)});
      });
    } catch (e) {
      rethrow;
    }
  }

  // ── Reject Friend Request ──
  Future<void> rejectFriendRequest(String senderHandle) async {
    final requestDocId = '${senderHandle}_$_currentUserHandle';
    final requestRef = _db.collection('friend_requests').doc(requestDocId);
    
    final doc = await requestRef.get();
    if (doc.exists) {
      await requestRef.update({
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ── Cancel Sent Request ──
  Future<void> cancelFriendRequest(String receiverHandle) async {
    final requestDocId = '${_currentUserHandle}_$receiverHandle';
    await _db.collection('friend_requests').doc(requestDocId).delete();
  }

  // ── Unfriend ──
  Future<void> unfriend(String otherHandle) async {
    final friendshipDocId = _friendshipId(_currentUserHandle, otherHandle);

    await _db.runTransaction((transaction) async {
      final friendshipRef = _db.collection('friendships').doc(friendshipDocId);
      transaction.delete(friendshipRef);
    });

    // Cleanup any old requests
    try {
      await _db.collection('friend_requests').doc('${_currentUserHandle}_$otherHandle').delete();
    } catch (_) {}
    try {
      await _db.collection('friend_requests').doc('${otherHandle}_$_currentUserHandle').delete();
    } catch (_) {}

    // Decrement counts
    await _incrementFriendCount(_currentUserHandle, -1);
    await _incrementFriendCount(otherHandle, -1);
  }

  // ── Block User ──
  Future<void> blockUser(String otherHandle) async {
    final blockDocId = '${_currentUserHandle}_$otherHandle';

    // Create block
    await _db.collection('blocks').doc(blockDocId).set({
      'blockerHandle': _currentUserHandle,
      'blockedHandle': otherHandle,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Remove friendship if exists
    final friendshipDocId = _friendshipId(_currentUserHandle, otherHandle);
    final friendshipDoc = await _db.collection('friendships').doc(friendshipDocId).get();
    if (friendshipDoc.exists) {
      await _db.collection('friendships').doc(friendshipDocId).delete();
      await _incrementFriendCount(_currentUserHandle, -1);
      await _incrementFriendCount(otherHandle, -1);
    }

    // Remove any pending requests
    try {
      await _db.collection('friend_requests').doc('${_currentUserHandle}_$otherHandle').delete();
    } catch (_) {}
    try {
      await _db.collection('friend_requests').doc('${otherHandle}_$_currentUserHandle').delete();
    } catch (_) {}
  }

  // ── Unblock User ──
  Future<void> unblockUser(String otherHandle) async {
    await _db.collection('blocks').doc('${_currentUserHandle}_$otherHandle').delete();
  }

  // ── Get Incoming Pending Requests (Stream) ──
  Stream<List<FriendRequest>> getPendingRequests() {
    return _db.collection('friend_requests')
        .where('receiverHandle', isEqualTo: _currentUserHandle)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => FriendRequest.fromMap(doc.data(), doc.id))
            .toList());
  }

  // ── Get Sent Pending Requests (Stream) ──
  Stream<List<FriendRequest>> getSentRequests() {
    return _db.collection('friend_requests')
        .where('senderHandle', isEqualTo: _currentUserHandle)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => FriendRequest.fromMap(doc.data(), doc.id))
            .toList());
  }

  // ── Get Friends List (Stream) ──
  Stream<List<Friendship>> getFriendsList() {
    return _db.collection('friendships')
        .where('users', arrayContains: _currentUserHandle)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Friendship.fromMap(doc.data(), doc.id))
            .toList());
  }

  // ── Get Blocked Users List ──
  Stream<List<BlockEntry>> getBlockedUsers() {
    return _db.collection('blocks')
        .where('blockerHandle', isEqualTo: _currentUserHandle)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => BlockEntry.fromMap(doc.data(), doc.id))
            .toList());
  }

  // ── Get Pending Request Count (for badge) ──
  Stream<int> getPendingRequestCount() {
    return _db.collection('friend_requests')
        .where('receiverHandle', isEqualTo: _currentUserHandle)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  // ── Check if two users are friends ──
  Future<bool> areFriends(String otherHandle) async {
    final doc = await _db.collection('friendships')
        .doc(_friendshipId(_currentUserHandle, otherHandle)).get();
    return doc.exists;
  }

  // ── Helper: lookup user data by handle ──
  Future<Map<String, dynamic>?> getUserByHandle(String handle) async {
    final snap = await _db.collection('users')
        .where('handle', isEqualTo: handle)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.data();
  }

  // ── Helper: Increment friend count ──
  Future<void> _incrementFriendCount(String handle, int delta) async {
    await _db.collection('profiles').doc(handle).update({
      'friendCount': FieldValue.increment(delta),
    }).catchError((_) {}); // Ignore if profile doesn't exist
  }
}
