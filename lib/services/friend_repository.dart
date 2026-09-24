import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/friend_request_model.dart';
import '../models/friendship_model.dart';
import '../models/block_model.dart';
import 'notification_service.dart';

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

  String get currentUserHandle {
    if (_currentUserHandle.isEmpty) {
      final u = FirebaseAuth.instance.currentUser;
      if (u?.displayName != null && u!.displayName!.isNotEmpty) {
        _currentUserHandle = u.displayName!.replaceAll('@', '').trim();
      }
    }
    return _currentUserHandle;
  }

  set currentUserHandle(String handle) =>
      _currentUserHandle = handle.replaceAll('@', '').trim();

  // ── Helper: Resolve current user handle from Firestore if uninitialized ──
  Future<String> _resolveCurrentUserHandle() async {
    if (_currentUserHandle.isNotEmpty) return _currentUserHandle;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return '';
    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists && userDoc.data()?['handle'] != null) {
        _currentUserHandle = userDoc.data()!['handle'].toString().replaceAll('@', '').trim();
        return _currentUserHandle;
      }
      final profSnap = await _db.collection('profiles').where('ownerUid', isEqualTo: uid).limit(1).get();
      if (profSnap.docs.isNotEmpty) {
        _currentUserHandle = profSnap.docs.first.id.replaceAll('@', '').trim();
        return _currentUserHandle;
      }
    } catch (_) {}
    return '';
  }

  // ── Helper: Deterministic canonical friendship ID (lowercase) ──
  String _friendshipId(String a, String b) {
    final cleanA = a.replaceAll('@', '').trim().toLowerCase();
    final cleanB = b.replaceAll('@', '').trim().toLowerCase();
    final sorted = [cleanA, cleanB]..sort();
    return sorted.join('_');
  }

  // ── Helper: Deterministic legacy friendship ID (raw casing) ──
  String _friendshipIdRaw(String a, String b) {
    final cleanA = a.replaceAll('@', '').trim();
    final cleanB = b.replaceAll('@', '').trim();
    final sorted = [cleanA, cleanB]..sort();
    return sorted.join('_');
  }

  // ── Check relationship status with another user ──
  Future<RelationshipStatus> getRelationshipStatus(String otherHandle) async {
    String me = _currentUserHandle.replaceAll('@', '').trim();
    if (me.isEmpty) {
      me = await _resolveCurrentUserHandle();
    }
    final them = otherHandle.replaceAll('@', '').trim();
    if (me.isEmpty || them.isEmpty) return RelationshipStatus.none;
    if (me.toLowerCase() == them.toLowerCase()) return RelationshipStatus.none;

    final myUid = FirebaseAuth.instance.currentUser?.uid;

    // 1. Check if blocked by me (raw & lowercase)
    try {
      final blockByMe = await _db.collection('blocks')
          .doc('${me}_$them').get();
      if (blockByMe.exists) return RelationshipStatus.blockedByMe;
      final blockByMeLower = await _db.collection('blocks')
          .doc('${me.toLowerCase()}_${them.toLowerCase()}').get();
      if (blockByMeLower.exists) return RelationshipStatus.blockedByMe;
    } catch (_) {}

    // 2. Check if blocked by them (raw & lowercase)
    try {
      final blockByThem = await _db.collection('blocks')
          .doc('${them}_$me').get();
      if (blockByThem.exists) return RelationshipStatus.blockedByThem;
      final blockByThemLower = await _db.collection('blocks')
          .doc('${them.toLowerCase()}_${me.toLowerCase()}').get();
      if (blockByThemLower.exists) return RelationshipStatus.blockedByThem;
    } catch (_) {}

    // 3. Check if friends (Canonical lowercase ID, Legacy raw ID, users query, usersUids query)
    try {
      final friendshipDoc = await _db.collection('friendships')
          .doc(_friendshipId(me, them)).get();
      if (friendshipDoc.exists) return RelationshipStatus.friends;
    } catch (_) {}

    try {
      final friendshipDocRaw = await _db.collection('friendships')
          .doc(_friendshipIdRaw(me, them)).get();
      if (friendshipDocRaw.exists) return RelationshipStatus.friends;
    } catch (_) {}

    // Fallback A: Search by users array
    try {
      final qUsers = await _db.collection('friendships')
          .where('users', arrayContainsAny: [
            me,
            them,
            me.toLowerCase(),
            them.toLowerCase(),
            '@$me',
            '@$them',
          ])
          .limit(10)
          .get();
      for (final doc in qUsers.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        final rawUsers = data?['users'];
        if (rawUsers is List) {
          final list = rawUsers.map((u) => u.toString().replaceAll('@', '').trim().toLowerCase()).toList();
          if (list.contains(me.toLowerCase()) && list.contains(them.toLowerCase())) {
            return RelationshipStatus.friends;
          }
        }
      }
    } catch (_) {}

    // Fallback B: Search by usersUids array (matching current user UID)
    if (myUid != null && myUid.isNotEmpty) {
      try {
        final qUids = await _db.collection('friendships')
            .where('usersUids', arrayContains: myUid)
            .limit(20)
            .get();
        for (final doc in qUids.docs) {
          final data = doc.data() as Map<String, dynamic>?;
          final rawUsers = data?['users'];
          if (rawUsers is List) {
            final list = rawUsers.map((u) => u.toString().replaceAll('@', '').trim().toLowerCase()).toList();
            if (list.contains(them.toLowerCase())) {
              return RelationshipStatus.friends;
            }
          }
        }
      } catch (_) {}
    }

    // 4. Check if I sent a pending request (raw & lowercase)
    try {
      final sentRequest = await _db.collection('friend_requests')
          .doc('${me}_$them').get();
      final sentData = sentRequest.data();
      if (sentRequest.exists && sentData?['status'] == 'pending') {
        return RelationshipStatus.requestSentByMe;
      }
      final sentRequestLower = await _db.collection('friend_requests')
          .doc('${me.toLowerCase()}_${them.toLowerCase()}').get();
      final sentLowerData = sentRequestLower.data();
      if (sentRequestLower.exists && sentLowerData?['status'] == 'pending') {
        return RelationshipStatus.requestSentByMe;
      }
    } catch (_) {}

    // 5. Check if they sent me a pending request (raw & lowercase)
    try {
      final receivedRequest = await _db.collection('friend_requests')
          .doc('${them}_$me').get();
      final recvData = receivedRequest.data();
      if (receivedRequest.exists && recvData?['status'] == 'pending') {
        return RelationshipStatus.requestReceivedByMe;
      }
      final receivedRequestLower = await _db.collection('friend_requests')
          .doc('${them.toLowerCase()}_${me.toLowerCase()}').get();
      final recvLowerData = receivedRequestLower.data();
      if (receivedRequestLower.exists && recvLowerData?['status'] == 'pending') {
        return RelationshipStatus.requestReceivedByMe;
      }
    } catch (_) {}

    return RelationshipStatus.none;
  }

  // ── Send Friend Request ──
  Future<void> sendFriendRequest(String receiverHandle) async {
    String me = _currentUserHandle.replaceAll('@', '').trim();
    if (me.isEmpty) {
      me = await _resolveCurrentUserHandle();
    }
    final them = receiverHandle.replaceAll('@', '').trim();
    if (them.isEmpty) throw Exception('Target user not specified');
    if (them.toLowerCase() == me.toLowerCase()) throw Exception('Cannot friend yourself');

    final status = await getRelationshipStatus(them);
    if (status != RelationshipStatus.none) {
      throw Exception('Cannot send request: relationship already exists');
    }

    // Fetch receiverUid from profiles with case-insensitive fallback
    var profileDoc = await _db.collection('profiles').doc(them).get();
    if (!profileDoc.exists) {
      profileDoc = await _db.collection('profiles').doc(them.toLowerCase()).get();
    }
    
    String? receiverUid;
    if (profileDoc.exists) {
      final pData = profileDoc.data();
      receiverUid = pData?['ownerUid'] ?? pData?['uid'] ?? pData?['userId'];
    }

    // Fallback: search in users collection by handle if receiverUid is still null
    if (receiverUid == null || receiverUid.isEmpty) {
      try {
        final userSnap = await _db.collection('users')
            .where('handle', isEqualTo: them)
            .limit(1)
            .get();
        if (userSnap.docs.isNotEmpty) {
          receiverUid = userSnap.docs.first.id;
        } else {
          final userSnapLower = await _db.collection('users')
              .where('handle', isEqualTo: them.toLowerCase())
              .limit(1)
              .get();
          if (userSnapLower.docs.isNotEmpty) {
            receiverUid = userSnapLower.docs.first.id;
          }
        }
      } catch (_) {}
    }

    final senderUid = FirebaseAuth.instance.currentUser?.uid;
    if (senderUid == null) throw Exception('Not authenticated.');

    final docId = '${me.toLowerCase()}_${them.toLowerCase()}';
    await _db.collection('friend_requests').doc(docId).set({
      'senderHandle': me,
      'senderUid': senderUid,
      'receiverHandle': them,
      'receiverUid': receiverUid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Also set raw docId for backwards compatibility if case differs
    final rawDocId = '${me}_$them';
    if (rawDocId != docId) {
      try {
        await _db.collection('friend_requests').doc(rawDocId).set({
          'senderHandle': me,
          'senderUid': senderUid,
          'receiverHandle': them,
          'receiverUid': receiverUid,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    // Dispatch notification
    await NotificationService().sendNotification(
      targetHandle: them,
      targetUid: receiverUid,
      title: 'New Friend Request',
      body: '@$me sent you a friend request',
      data: {
        'type': 'friend_request',
        'senderHandle': me,
      },
    );
  }

  // ── Accept Friend Request ──
  Future<void> acceptFriendRequest(String senderHandle) async {
    String me = _currentUserHandle.replaceAll('@', '').trim();
    if (me.isEmpty) {
      me = await _resolveCurrentUserHandle();
    }
    final them = senderHandle.replaceAll('@', '').trim();
    if (them.isEmpty || me.isEmpty || them.toLowerCase() == me.toLowerCase()) return;

    final requestDocId = '${them}_$me';
    final requestDocIdLower = '${them.toLowerCase()}_${me.toLowerCase()}';
    final friendshipDocId = _friendshipId(them, me);
    final friendshipDocIdRaw = _friendshipIdRaw(them, me);

    try {
      // 1. Check if friendship document already exists
      final f1 = await _db.collection('friendships').doc(friendshipDocId).get();
      final f2 = (friendshipDocId != friendshipDocIdRaw)
          ? await _db.collection('friendships').doc(friendshipDocIdRaw).get()
          : null;
      final bool alreadyFriends = f1.exists || (f2 != null && f2.exists);

      // 2. Fetch sender UID if available
      String? senderUid;
      try {
        final rDoc = await _db.collection('friend_requests').doc(requestDocIdLower).get();
        if (rDoc.exists) {
          senderUid = rDoc.data()?['senderUid']?.toString();
        } else {
          final rDocRaw = await _db.collection('friend_requests').doc(requestDocId).get();
          if (rDocRaw.exists) {
            senderUid = rDocRaw.data()?['senderUid']?.toString();
          }
        }
      } catch (_) {}

      if (senderUid == null || senderUid.isEmpty) {
        try {
          var pDoc = await _db.collection('profiles').doc(them).get();
          if (!pDoc.exists) {
            pDoc = await _db.collection('profiles').doc(them.toLowerCase()).get();
          }
          if (pDoc.exists) {
            senderUid = pDoc.data()?['ownerUid'] ?? pDoc.data()?['uid'] ?? pDoc.data()?['userId'];
          }
        } catch (_) {}
      }

      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final usersUidsList = <String>[];
      if (senderUid != null && senderUid.toString().isNotEmpty) {
        usersUidsList.add(senderUid.toString());
      }
      if (currentUid != null && currentUid.isNotEmpty && !usersUidsList.contains(currentUid)) {
        usersUidsList.add(currentUid);
      }

      // 3. Mark friend request documents as accepted
      final batch = _db.batch();
      final r1 = _db.collection('friend_requests').doc(requestDocIdLower);
      final r2 = _db.collection('friend_requests').doc(requestDocId);
      batch.set(r1, {
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (requestDocId != requestDocIdLower) {
        batch.set(r2, {
          'status': 'accepted',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // 4. If not already friends, create friendship doc and update friend counts
      if (!alreadyFriends) {
        final friendshipRef = _db.collection('friendships').doc(friendshipDocId);
        batch.set(friendshipRef, {
          'users': [them, me, them.toLowerCase(), me.toLowerCase()],
          'usersUids': usersUidsList,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final senderProfileRef = _db.collection('profiles').doc(them);
        final currentProfileRef = _db.collection('profiles').doc(me);
        batch.set(senderProfileRef, {'friendCount': FieldValue.increment(1)}, SetOptions(merge: true));
        batch.set(currentProfileRef, {'friendCount': FieldValue.increment(1)}, SetOptions(merge: true));
      }

      await batch.commit();

      // Dispatch acceptance notification only if newly friended
      if (!alreadyFriends) {
        NotificationService().sendNotification(
          targetHandle: them,
          title: 'Friend Request Accepted',
          body: '@$me accepted your friend request! Tap to start chatting.',
          data: {
            'type': 'chat',
            'partnerHandle': me,
            'senderHandle': me,
          },
        );
      }
    } catch (e) {
      debugPrint('[FriendRepo] Error in acceptFriendRequest: $e');
      rethrow;
    }
  }

  // ── Reject Friend Request ──
  Future<void> rejectFriendRequest(String senderHandle) async {
    String me = _currentUserHandle.replaceAll('@', '').trim();
    if (me.isEmpty) me = await _resolveCurrentUserHandle();
    final them = senderHandle.replaceAll('@', '').trim();
    
    final r1 = _db.collection('friend_requests').doc('${them}_$me');
    final r2 = _db.collection('friend_requests').doc('${them.toLowerCase()}_${me.toLowerCase()}');
    
    try {
      final doc1 = await r1.get();
      if (doc1.exists) {
        await r1.update({'status': 'rejected', 'updatedAt': FieldValue.serverTimestamp()});
      }
    } catch (_) {}
    try {
      final doc2 = await r2.get();
      if (doc2.exists) {
        await r2.update({'status': 'rejected', 'updatedAt': FieldValue.serverTimestamp()});
      }
    } catch (_) {}
  }

  // ── Cancel Sent Request ──
  Future<void> cancelFriendRequest(String receiverHandle) async {
    String me = _currentUserHandle.replaceAll('@', '').trim();
    if (me.isEmpty) me = await _resolveCurrentUserHandle();
    final them = receiverHandle.replaceAll('@', '').trim();

    try {
      await _db.collection('friend_requests').doc('${me}_$them').delete();
    } catch (_) {}
    try {
      await _db.collection('friend_requests').doc('${me.toLowerCase()}_${them.toLowerCase()}').delete();
    } catch (_) {}
  }

  // ── Unfriend ──
  Future<void> unfriend(String otherHandle) async {
    String me = _currentUserHandle.replaceAll('@', '').trim();
    if (me.isEmpty) me = await _resolveCurrentUserHandle();
    final them = otherHandle.replaceAll('@', '').trim();
    final friendshipDocId = _friendshipId(me, them);
    final friendshipDocIdRaw = _friendshipIdRaw(me, them);

    try {
      await _db.collection('friendships').doc(friendshipDocId).delete();
    } catch (_) {}
    try {
      await _db.collection('friendships').doc(friendshipDocIdRaw).delete();
    } catch (_) {}

    // Cleanup any old requests
    try {
      await _db.collection('friend_requests').doc('${me}_$them').delete();
      await _db.collection('friend_requests').doc('${me.toLowerCase()}_${them.toLowerCase()}').delete();
    } catch (_) {}
    try {
      await _db.collection('friend_requests').doc('${them}_$me').delete();
      await _db.collection('friend_requests').doc('${them.toLowerCase()}_${me.toLowerCase()}').delete();
    } catch (_) {}

    // Decrement counts
    await _incrementFriendCount(me, -1);
    await _incrementFriendCount(them, -1);
  }

  // ── Block User ──
  Future<void> blockUser(String otherHandle) async {
    String me = _currentUserHandle.replaceAll('@', '').trim();
    if (me.isEmpty) me = await _resolveCurrentUserHandle();
    final them = otherHandle.replaceAll('@', '').trim();
    final blockDocId = '${me.toLowerCase()}_${them.toLowerCase()}';

    // Create block
    await _db.collection('blocks').doc(blockDocId).set({
      'blockerHandle': me,
      'blockerUid': FirebaseAuth.instance.currentUser?.uid,
      'blockedHandle': them,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Remove friendship if exists
    final friendshipDocId = _friendshipId(me, them);
    final friendshipDocIdRaw = _friendshipIdRaw(me, them);
    try {
      await _db.collection('friendships').doc(friendshipDocId).delete();
    } catch (_) {}
    try {
      await _db.collection('friendships').doc(friendshipDocIdRaw).delete();
    } catch (_) {}
    await _incrementFriendCount(me, -1);
    await _incrementFriendCount(them, -1);

    // Remove any pending requests
    try {
      await _db.collection('friend_requests').doc('${me}_$them').delete();
      await _db.collection('friend_requests').doc('${me.toLowerCase()}_${them.toLowerCase()}').delete();
    } catch (_) {}
    try {
      await _db.collection('friend_requests').doc('${them}_$me').delete();
      await _db.collection('friend_requests').doc('${them.toLowerCase()}_${me.toLowerCase()}').delete();
    } catch (_) {}
  }

  // ── Unblock User ──
  Future<void> unblockUser(String otherHandle) async {
    String me = _currentUserHandle.replaceAll('@', '').trim();
    if (me.isEmpty) me = await _resolveCurrentUserHandle();
    final them = otherHandle.replaceAll('@', '').trim();
    try {
      await _db.collection('blocks').doc('${me}_$them').delete();
    } catch (_) {}
    try {
      await _db.collection('blocks').doc('${me.toLowerCase()}_${them.toLowerCase()}').delete();
    } catch (_) {}
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
    final status = await getRelationshipStatus(otherHandle);
    return status == RelationshipStatus.friends;
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
    final clean = handle.replaceAll('@', '').trim();
    if (clean.isEmpty) return;
    await _db.collection('profiles').doc(clean).set({
      'friendCount': FieldValue.increment(delta),
    }, SetOptions(merge: true)).catchError((_) {});
  }
}
