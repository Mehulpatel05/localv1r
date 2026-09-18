import 'package:flutter/foundation.dart';
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
  set currentUserHandle(String handle) =>
      _currentUserHandle = handle.replaceAll('@', '').trim();

  // ── Helper: Deterministic friendship ID ──
  String _friendshipId(String a, String b) {
    final cleanA = a.replaceAll('@', '').trim();
    final cleanB = b.replaceAll('@', '').trim();
    final sorted = [cleanA, cleanB]..sort();
    return sorted.join('_');
  }

  // ── Check relationship status with another user ──
  Future<RelationshipStatus> getRelationshipStatus(String otherHandle) async {
    final me = _currentUserHandle.replaceAll('@', '').trim();
    final them = otherHandle.replaceAll('@', '').trim();
    if (me.isEmpty || them.isEmpty) return RelationshipStatus.none;

    // Check if blocked by me
    try {
      final blockByMe = await _db.collection('blocks')
          .doc('${me}_$them').get();
      if (blockByMe.exists) return RelationshipStatus.blockedByMe;
    } catch (_) {}

    // Check if blocked by them
    try {
      final blockByThem = await _db.collection('blocks')
          .doc('${them}_$me').get();
      if (blockByThem.exists) return RelationshipStatus.blockedByThem;
    } catch (_) {}

    // Check if friends
    try {
      final friendshipDoc = await _db.collection('friendships')
          .doc(_friendshipId(me, them)).get();
      if (friendshipDoc.exists) return RelationshipStatus.friends;
    } catch (_) {}

    // Check if I sent a request
    try {
      final sentRequest = await _db.collection('friend_requests')
          .doc('${me}_$them').get();
      if (sentRequest.exists && sentRequest.data()?['status'] == 'pending') {
        return RelationshipStatus.requestSentByMe;
      }
    } catch (_) {}

    // Check if they sent me a request
    try {
      final receivedRequest = await _db.collection('friend_requests')
          .doc('${them}_$me').get();
      if (receivedRequest.exists && receivedRequest.data()?['status'] == 'pending') {
        return RelationshipStatus.requestReceivedByMe;
      }
    } catch (_) {}

    return RelationshipStatus.none;
  }

  // ── Send Friend Request ──
  Future<void> sendFriendRequest(String receiverHandle) async {
    final me = _currentUserHandle.replaceAll('@', '').trim();
    final them = receiverHandle.replaceAll('@', '').trim();
    if (them == me) throw Exception('Cannot friend yourself');

    final status = await getRelationshipStatus(them);
    if (status != RelationshipStatus.none) {
      throw Exception('Cannot send request: relationship already exists');
    }

    // Fetch receiverUid from profiles
    final profileDoc = await _db.collection('profiles').doc(them).get();
    if (!profileDoc.exists) {
      throw Exception('User not found.');
    }
    final receiverUid = profileDoc.data()?['ownerUid'];
    if (receiverUid == null) {
      throw Exception('User profile is incomplete.');
    }

    final senderUid = FirebaseAuth.instance.currentUser?.uid;
    if (senderUid == null) throw Exception('Not authenticated.');

    final docId = '${me}_$them';
    await _db.collection('friend_requests').doc(docId).set({
      'senderHandle': me,
      'senderUid': senderUid,
      'receiverHandle': them,
      'receiverUid': receiverUid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Accept Friend Request ──
  Future<void> acceptFriendRequest(String senderHandle) async {
    final me = _currentUserHandle.replaceAll('@', '').trim();
    final them = senderHandle.replaceAll('@', '').trim();
    final requestDocId = '${them}_$me';
    final friendshipDocId = _friendshipId(them, me);

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
          'users': [them, me],
          'usersUids': [doc.data()?['senderUid'], FirebaseAuth.instance.currentUser?.uid],
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Update friend counts atomically
        final senderProfileRef = _db.collection('profiles').doc(them);
        final currentProfileRef = _db.collection('profiles').doc(me);
        
        transaction.update(senderProfileRef, {'friendCount': FieldValue.increment(1)});
        transaction.update(currentProfileRef, {'friendCount': FieldValue.increment(1)});
      });
    } catch (e) {
      rethrow;
    }
  }

  // ── Reject Friend Request ──
  Future<void> rejectFriendRequest(String senderHandle) async {
    final me = _currentUserHandle.replaceAll('@', '').trim();
    final them = senderHandle.replaceAll('@', '').trim();
    final requestDocId = '${them}_$me';
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
    final me = _currentUserHandle.replaceAll('@', '').trim();
    final them = receiverHandle.replaceAll('@', '').trim();
    final requestDocId = '${me}_$them';
    await _db.collection('friend_requests').doc(requestDocId).delete();
  }

  // ── Unfriend ──
  Future<void> unfriend(String otherHandle) async {
    final me = _currentUserHandle.replaceAll('@', '').trim();
    final them = otherHandle.replaceAll('@', '').trim();
    final friendshipDocId = _friendshipId(me, them);

    await _db.runTransaction((transaction) async {
      final friendshipRef = _db.collection('friendships').doc(friendshipDocId);
      transaction.delete(friendshipRef);
    });

    // Cleanup any old requests
    try {
      await _db.collection('friend_requests').doc('${me}_$them').delete();
    } catch (_) {}
    try {
      await _db.collection('friend_requests').doc('${them}_$me').delete();
    } catch (_) {}

    // Decrement counts
    await _incrementFriendCount(me, -1);
    await _incrementFriendCount(them, -1);
  }

  // ── Block User ──
  Future<void> blockUser(String otherHandle) async {
    final me = _currentUserHandle.replaceAll('@', '').trim();
    final them = otherHandle.replaceAll('@', '').trim();
    final blockDocId = '${me}_$them';

    // Create block
    await _db.collection('blocks').doc(blockDocId).set({
      'blockerHandle': me,
      'blockerUid': FirebaseAuth.instance.currentUser?.uid,
      'blockedHandle': them,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Remove friendship if exists
    final friendshipDocId = _friendshipId(me, them);
    final friendshipDoc = await _db.collection('friendships').doc(friendshipDocId).get();
    if (friendshipDoc.exists) {
      await _db.collection('friendships').doc(friendshipDocId).delete();
      await _incrementFriendCount(me, -1);
      await _incrementFriendCount(them, -1);
    }

    // Remove any pending requests
    try {
      await _db.collection('friend_requests').doc('${me}_$them').delete();
    } catch (_) {}
    try {
      await _db.collection('friend_requests').doc('${them}_$me').delete();
    } catch (_) {}
  }

  // ── Unblock User ──
  Future<void> unblockUser(String otherHandle) async {
    final me = _currentUserHandle.replaceAll('@', '').trim();
    final them = otherHandle.replaceAll('@', '').trim();
    await _db.collection('blocks').doc('${me}_$them').delete();
  }

  // ── Get Incoming Pending Requests (Stream) ──
  Stream<List<FriendRequest>> getPendingRequests({int limit = 100}) {
    final me = _currentUserHandle.replaceAll('@', '').trim();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (me.isEmpty && (uid == null || uid.isEmpty)) return Stream.value([]);

    Query query = _db.collection('friend_requests');
    if (uid != null && uid.isNotEmpty) {
      query = query.where('receiverUid', isEqualTo: uid);
    } else {
      query = query.where('receiverHandle', whereIn: [me, '@$me']);
    }

    return query
        .where('status', isEqualTo: 'pending')
        .limit(limit)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((doc) => FriendRequest.fromMap(doc.data() as Map<String, dynamic>, doc.id))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        })
        .handleError((error) {
          debugPrint('Error loading pending requests: $error');
          return <FriendRequest>[];
        });
  }

  // ── Get Sent Pending Requests (Stream) ──
  Stream<List<FriendRequest>> getSentRequests({int limit = 100}) {
    final me = _currentUserHandle.replaceAll('@', '').trim();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (me.isEmpty && (uid == null || uid.isEmpty)) return Stream.value([]);

    Query query = _db.collection('friend_requests');
    if (uid != null && uid.isNotEmpty) {
      query = query.where('senderUid', isEqualTo: uid);
    } else {
      query = query.where('senderHandle', whereIn: [me, '@$me']);
    }

    return query
        .where('status', isEqualTo: 'pending')
        .limit(limit)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((doc) => FriendRequest.fromMap(doc.data() as Map<String, dynamic>, doc.id))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        })
        .handleError((error) {
          debugPrint('Error loading sent requests: $error');
          return <FriendRequest>[];
        });
  }

  // ── Get Friends List (Stream) ──
  Stream<List<Friendship>> getFriendsList({int limit = 200}) {
    final me = _currentUserHandle.replaceAll('@', '').trim();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (me.isEmpty && (uid == null || uid.isEmpty)) return Stream.value([]);

    Query query = _db.collection('friendships');
    if (uid != null && uid.isNotEmpty) {
      query = query.where('usersUids', arrayContains: uid);
    } else {
      query = query.where('users', arrayContainsAny: [me, '@$me']);
    }

    return query
        .limit(limit)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((doc) => Friendship.fromMap(doc.data() as Map<String, dynamic>, doc.id))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        })
        .handleError((error) {
          debugPrint('Error loading friends list: $error');
          return <Friendship>[];
        });
  }

  // ── Get Blocked Users List ──
  Stream<List<BlockEntry>> getBlockedUsers({int limit = 100}) {
    final me = _currentUserHandle.replaceAll('@', '').trim();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (me.isEmpty && (uid == null || uid.isEmpty)) return Stream.value([]);

    Query query = _db.collection('blocks');
    if (uid != null && uid.isNotEmpty) {
      query = query.where('blockerUid', isEqualTo: uid);
    } else {
      query = query.where('blockerHandle', whereIn: [me, '@$me']);
    }

    return query
        .limit(limit)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((doc) => BlockEntry.fromMap(doc.data() as Map<String, dynamic>, doc.id))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        })
        .handleError((error) {
          debugPrint('Error loading blocked users: $error');
          return <BlockEntry>[];
        });
  }

  // ── Get Pending Request Count (for badge) ──
  Stream<int> getPendingRequestCount() {
    final me = _currentUserHandle.replaceAll('@', '').trim();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (me.isEmpty && (uid == null || uid.isEmpty)) return Stream.value(0);

    Query query = _db.collection('friend_requests');
    if (uid != null && uid.isNotEmpty) {
      query = query.where('receiverUid', isEqualTo: uid);
    } else {
      query = query.where('receiverHandle', whereIn: [me, '@$me']);
    }

    return query
        .where('status', isEqualTo: 'pending')
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.length)
        .handleError((error) {
          return 0;
        });
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
