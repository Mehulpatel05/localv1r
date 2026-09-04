# 🔍 localv1 (Vadodara Local) — Full Project Audit

**Scanned:** Flutter app (`lib/`, 48 Dart files) + backend (`functions/index.js` Cloud Functions) + `firebase.json` + FastAPI backend references.
**Date:** 2026-09-04
**Verdict (short):** The app *looks* finished but has **one deep architectural crack** (two different login systems that don't talk to each other) and **no server-side security** (no Firestore rules in the repo). Fix these two first — everything else is secondary.

> **Hinglish note:** Sabse pehle 2 cheezein fix karo — (1) **login system ek karo** (abhi Google login aur FastAPI backend alag-alag hain, isliye post/vote/comment Google user ke liye kaam nahi karega), aur (2) **Firestore security rules add karo** (abhi database khula ho sakta hai — koi bhi kisi ka bhi chat/friend/community padh/likh sakta hai). Baaki sab list neeche hai, priority ke saath.

---

## 1. Architecture — how it actually works today

| Layer | What it does | Auth used |
|---|---|---|
| **FastAPI backend** (`localv1r.onrender.com`) | Posts, comments, votes, reports, media upload (Telegram proxy) | `Bearer session_token` (from device register) |
| **Firebase Auth (Google)** | Actual login entry point (`main.dart` → `GoogleLoginScreen`) | Firebase `user.uid` |
| **Firestore (direct from client)** | Friends, friend requests, blocks, communities, community chat, personal chat, users, FCM tokens | ⚠️ **client-set handle string — no server check** |
| **Cloud Functions** (`functions/index.js`) | Push notifications on friend request + chat message | Trigger only, enforces nothing |
| **Device register** (`device_register_screen.dart`) | Play Integrity attestation → `Anon#xxxx` handle + `session_token` | Orphaned (not reachable from `main.dart`) |

### 🚨 The central problem: **two identity systems that don't connect**

1. `main.dart:81` sends new users to **Google Sign-In**, not device registration.
2. Google login (`create_handle_screen.dart:74`) lets the user **type any username** and stores it in `users/{uid}.handle`.
3. But `PostRepository` talks to the **FastAPI backend** using a `session_token` that is **only created by the device-register flow** (`device_register_screen.dart:89`) — which the Google path never runs.

**Consequence (confirmed in code):** After Google login there is no `session_token`, so `PostRepository._getAuthHeaders()` (`post_repository.dart:375`) sends `Authorization: Bearer ` (empty). **Creating a post, voting, commenting, reporting will fail auth on the backend for every real (Google) user.** Only reading posts works (it uses unauthenticated headers).

👉 **You must pick ONE identity model** and wire everything to it. Recommended: keep Google/Firebase Auth as the login, and make the FastAPI backend verify the **Firebase ID token** (not a separate session_token). See §8.

---

## 2. 🔴 CRITICAL — Security (fix before any public release)

### S1. No Firestore / Storage security rules in the project
- `firebase.json` has **no `firestore` or `storage` rules block**, and there is **no `firestore.rules` / `storage.rules` file** anywhere in the repo.
- All of these run as **direct client writes** with a client-controlled handle: `friendships`, `friend_requests`, `blocks`, `communities`, `community_members`, `community_messages`, `chats/*/messages`, `users`.
- **If the database is in test mode / open rules (very common in unfinished projects), then anyone with the public API key can:** read every private DM, read all users' emails + FCM tokens, send messages/friend-requests/posts **as any other handle** (full impersonation), delete communities, inflate `friendCount`/`memberCount`, unblock themselves.
- **Fix:** Add and deploy real rules today. Starter file in §9. Also add `"firestore": {"rules": "firestore.rules"}` to `firebase.json`.
- **Severity: CRITICAL.**

### S2. Identity is a client-set string, not a verified UID
- `friend_repository.dart:17-20`, `community_repository.dart:6-9`: `_currentUserHandle` is just a setter. Every write (`sendFriendRequest`, `sendMessage`, `createCommunity`, chat `_sendMessage` at `personal_chat_screen.dart:53`) trusts this string as the author.
- Because Firestore only knows `request.auth.uid` (Google) — **not the handle** — rules can't even verify the handle matches the user unless you store a `uid ↔ handle` mapping and check it.
- **Fix:** Write `authorUid: request.auth.uid` on every doc and enforce `request.auth.uid == resource.data.authorUid` in rules. Map handle→uid in the `users` collection and validate.
- **Severity: CRITICAL.**

### S3. No Firebase App Check
- Nothing stops a script (not the app) from calling Firestore / the FastAPI backend directly with the public config.
- **Fix:** Enable **Firebase App Check** (Play Integrity on Android) and enforce it on Firestore + Functions; have the FastAPI backend require a valid Firebase ID token too.
- **Severity: High.**

### S4. Play Integrity attestation is bypassable by design
- `device_info_service.dart:63,67`: on **any** exception (or on iOS/other), it returns a **predictable** string `"simulated_attestation_com.example.localv1_$requestHash"`.
- If the FastAPI backend accepts that (or doesn't strictly verify a real Google-signed integrity token), attestation is **theater** — anyone can send the simulated token and register.
- **Fix:** Backend must reject any token that isn't a valid, Google-signed Play Integrity verdict. Never trust the `simulated_...` fallback in production.
- **Severity: High (backend-dependent).**

### S5. Blocking is only enforced on the client
- `friend_repository.getRelationshipStatus()` checks blocks, but a blocked user can still write to `chats/*/messages`, `community_messages`, or send posts because nothing server-side stops them.
- **Fix:** Enforce block lists in Firestore rules / backend, not just in the UI.
- **Severity: High.**

### S6. PII + FCM tokens in a client-readable collection
- `users` docs hold `email` (`create_handle_screen.dart:76`) and `fcmToken` (`notification_service.dart:95-98`). With open rules these are readable by anyone → spam, targeted phishing, token harvesting.
- **Fix:** Rules: a user can read only their own `users` doc; expose a separate public `profiles/{handle}` doc with only non-sensitive fields (handle, friendCount).
- **Severity: High.**

### S7. Overstated privacy claims in UI
- `device_register_screen.dart:237` says the install ID is *"Stable across uninstalls"* while `:172` says *"Absolute privacy… no… passwords"* and `:325` claims *"De-anonymizing you is cryptographically impossible."* Using Android SSAID/ANDROID_ID as a stable ID is a **tracking identifier**, which contradicts "absolute privacy." These claims are also a Play Store policy risk.
- **Fix:** Remove absolute claims; describe the real behavior accurately.
- **Severity: Medium (legal/trust).**

> ✅ **Not a leak:** the API keys in `firebase_options.dart:44-80` are *public client identifiers* — normal for Firebase. Still, restrict them in Google Cloud Console (API restrictions) and rely on App Check + rules for actual security.

---

## 3. 🟠 Logic bugs / correctness

### B1. Chat push notifications go to the wrong person (field-name mismatch)
- App writes message field **`senderHandle`** (`personal_chat_screen.dart:53`).
- Cloud Function reads **`senderId`** (`functions/index.js:74`), so `senderHandle` is `undefined`; then `receiverHandle = handles.find(h => h !== undefined)` picks `handles[0]` — **often the sender itself**, so the wrong user (or no one) is notified.
- **Fix:** Make both sides use the same field name (`senderHandle`), and derive the receiver from the stored `participants` array instead of splitting the chatId.
- **Severity: High (feature broken).**

### B2. `chatId` / doc IDs break when a handle contains `_`
- IDs are built by joining handles with `_`: `personal_chat_screen.dart:37`, `friend_repository._friendshipId:23`, blocks/requests (`friend_repository.dart:71,83,161`), `community_members` (`community_repository.dart:65`).
- Google users choose **free-text usernames with no validation** (`create_handle_screen.dart:46-51` only checks non-empty). A handle like `john_doe` makes `chatId = alice_john_doe`, which the Cloud Function's `split("_")` (`index.js:80`) turns into 3 parts → wrong receiver; and two different pairs can collide on the same ID.
- **Fix:** Validate handles to `^[a-z0-9]{3,20}$` (lowercase, no `_`/`#`/spaces). Prefer building IDs from **UIDs**, not handles.
- **Severity: High.**

### B3. Handle uniqueness has a race + is case-sensitive
- `create_handle_screen.dart:60-78`: `where(handle==).get()` then `set()` is **TOCTOU** — two users can grab the same handle at once. Also `John` vs `john` both allowed → impersonation.
- **Fix:** Reserve handles atomically via a `handles/{lowercaseHandle}` doc created in a transaction (fails if it exists); store/compare lowercased.
- **Severity: High.**

### B4. Friend counts drift (not atomic)
- `friend_repository.dart:109-111`: `_incrementFriendCount` runs **outside** the accept transaction; `unfriend`/`block` also increment separately (`:155-156,175-176`). A partial failure or double-tap desyncs counts.
- `acceptFriendRequest` (`:82-115`) never checks the request is still `'pending'`, so accepting twice sets the friendship again **and increments both counts again** → inflated counts.
- **Fix:** Do count updates inside the transaction; guard on `status == 'pending'` before accepting; make friendship creation idempotent.
- **Severity: Medium.**

### B5. Optimistic vote never reverts on failure
- `post_repository.dart:465-497`: UI vote is applied and saved locally; on backend failure the code only `debugPrint`s (`:495` even says *"Should revert optimistic UI in real app"*). Vote counts shown can drift from the server permanently.
- **Fix:** On non-200, roll back the local vote + counts and `notifyListeners()`.
- **Severity: Medium.**

### B6. `deletePostPermanently` has dead, duplicated catch blocks
- `post_repository.dart:347-352`: two identical `catch (e)` blocks; the second is unreachable dead code.
- **Fix:** Remove the duplicate; actually restore the optimistically-removed post if the delete fails.
- **Severity: Low (bug smell + no rollback).**

### B7. `PostRepository` recreated on every rebuild
- `main.dart:37`: `final postRepository = PostRepository();` is inside `build()`. Every rebuild spins up a new repository (new listeners/HTTP polling), leaking the old one.
- **Fix:** Hoist it (make the widget `StatefulWidget` and create it in `initState`, or provide it once via a Provider/`InheritedWidget`).
- **Severity: Medium (leak/perf).**

### B8. FCM token only saved for Firebase-auth users
- `notification_service.dart:92-101` writes the token to `users/{FirebaseAuth uid}`. This is fine for the Google path, but confirms the device-register/`Anon#` path (§1) is dead — under that path `currentUser == null` and **the token is never saved**, so notifications silently never arrive.
- **Fix:** Unify auth (§8); ensure every logged-in user has a `users/{uid}` doc before saving the token.
- **Severity: Medium.**

---

## 4. 🟡 Missing / half-built features

- **Notification tap does nothing.** `notification_service.dart:128-142` — both tap handlers only `debugPrint`; there's a comment *"Navigation can be handled here via a global navigator key"* but it's not implemented. Tapping a friend-request/chat notification won't open the relevant screen.
- **`FeedTab.nearby` is fake.** `post_repository.dart:12` defines it, but `posts` getter (`:83-88`) only handles `trending` vs everything-else; there is **no location/geo logic** anywhere. "Nearby" shows the same as "Latest."
- **Hardcoded demo posts injected into every feed.** `post_repository.dart:136-230` inserts fake `demo_shop_post`, `demo_room_post`, `demo_food_post`, `demo_event_post`, `demo_job_post`, `demo_service_post` on every refresh. Fine for a demo, **must be removed for production** (users will think they're real listings; one even has a fake HR email).
- **No "leave community", delete community, or moderation.** `community_repository.dart` only has create/join/send. No leave/kick/delete/report; `memberCount` can only go up.
- **Community membership not required to post.** `sendMessage` (`community_repository.dart:98-106`) never checks `isMember`. Anyone can post in any community.
- **No message pagination** in personal chat (`personal_chat_screen.dart:94-100`) or community chat (`community_repository.dart:38-47`) — both stream the **entire** message history (cost + slowness as chats grow).
- **Silent failures — empty catch blocks** swallow errors with no user feedback:
  `create_post_screen.dart:99`, `other_user_profile_sheet.dart:88`, `shop_post_screen.dart:130,135`, `room_post_screen.dart:132,137`, plus the `catch (_) {}` cleanup swallows in `friend_repository.dart:149,152,182,185`.
- **Client-side content filter is bypassable.** `core/utils/content_filter.dart` runs only on-device; real moderation must be server-side. Treat the client filter as UX only.
- **Orphaned code:** `device_register_screen.dart` + `HandleGenerator` (`Anon#` scheme) are unreachable from `main.dart`. Either wire them in or delete them to reduce confusion.

---

## 5. ⚙️ Performance & Firestore cost

- **N+1 reads:** `community_repository.getUserCommunities()` (`:12-28`) does one `get()` per membership. With many communities this is slow + costly. → Store enough community info on the membership doc, or batch with `whereIn` (chunks of 10/30).
- **Composite indexes missing.** Queries like `where(...).where(...).orderBy(...)` (`friend_repository.dart:194-203,206-215,239-245`, `community_repository.dart:38-47`) require Firestore composite indexes. There is **no `firestore.indexes.json`** — these will throw `FAILED_PRECONDITION` at runtime until you create each index (the error gives a console link). Commit the index file.
- **Unbounded queries:** chat + community messages have no `limit()`; feed `fetchPostsByUser` pulls `limit=100` and filters client-side (`post_repository.dart:502-545`) instead of a server `?author=` query.
- **Polling comments every 10s** in an infinite `while(true)` loop (`post_repository.dart:248-268`) — wasteful and has no backoff; prefer a real-time channel or at least exponential backoff + stop when off-screen.
- **Dead fields:** `_lastDoc` (`:27`) and `_lastVoteTime` (`:22`) are declared but never used.

---

## 6. 🧱 Code quality / architecture

- **Business logic lives in `setState` widgets** (chat writes directly to Firestore in `personal_chat_screen.dart`; auth logic inside screen `State`s). Move to repositories/services for testability.
- **No real state management.** A single `PostRepository extends ChangeNotifier` is passed by constructor through many screens; friends/communities repos are created ad-hoc. Consider Provider/Riverpod/Bloc and inject repositories once.
- **Duplicated category screens.** `jobs/food/events/shop/rooms/services` each have near-identical `_screen.dart` + `_post_screen.dart`. This is a lot of copy-paste (and the empty-catch bugs are duplicated across them). Extract a shared generic "category feed + create" widget parameterized by category.
- **Mixed concerns in `PostRepository`** (HTTP + local vote cache + UI filter/sort + demo data). Split into `PostApiClient`, `VoteStore`, and a view-model.
- **No tests at all** (no `test/` usage found for this logic). At minimum, unit-test `friend_repository`, handle validation, and `_getChatId`.
- **`print`/`debugPrint` everywhere** as the only error channel — add a logger and surface user-facing errors via SnackBars.

---

## 7. ✅ Prioritized action plan (do in this order)

**P0 — Security & broken auth (this week):**
1. Write + deploy `firestore.rules` and `storage.rules`; add them to `firebase.json`. (§9)
2. Decide ONE auth model (recommend Firebase Auth) and make the FastAPI backend verify the **Firebase ID token**, so posting works for real users. (§8)
3. Enable **Firebase App Check**; make the backend reject `simulated_...` attestation.
4. Lock down `users` (owner-read only); move public fields to `profiles/{handle}`.

**P1 — Correctness (next):**
5. Fix chat notification field mismatch `senderId`→`senderHandle`; derive receiver from `participants` (B1).
6. Validate handles `^[a-z0-9]{3,20}$`, lowercase, atomic uniqueness (B2, B3).
7. Make friend-count updates transactional + guard `status=='pending'` (B4).
8. Revert optimistic votes on failure (B5); fix duplicate catch in delete (B6).
9. Hoist `PostRepository` out of `build()` (B7).

**P2 — Features & polish:**
10. Remove hardcoded demo posts (§4) before launch.
11. Implement notification-tap navigation; add message pagination; add "leave community" + membership check on send.
12. Implement or hide `FeedTab.nearby`.
13. Add composite index file; replace client-side filtering with server queries.
14. Replace empty catch blocks with user-visible error handling.

**P3 — Structure:**
15. Introduce state management + inject repositories once; extract shared category widget; add unit tests; add a logger.

---

## 8. Recommended: unify auth (concrete)

Keep **Google/Firebase Auth** as the single login. Then:

1. On the Flutter side, get the Firebase ID token and send it to FastAPI:
   ```dart
   final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
   // header: 'Authorization': 'Bearer $idToken'
   ```
2. On FastAPI, verify it with the Firebase Admin SDK and **derive `authorHandle` from the verified token** — never trust `authorHandle` sent in the body (`post_repository.dart:428`).
3. Delete the parallel device-register/`session_token`/`Anon#` path (or, if you truly want anonymous device login, use **Firebase Anonymous Auth** so you still get a real `uid` for rules).

This single change makes posting work again **and** gives Firestore rules a real `request.auth.uid` to enforce.

---

## 9. Starter `firestore.rules` (adapt, then deploy)

> Assumes each social doc stores `authorUid` / `ownerUid` = the creator's Firebase UID, and `users/{uid}` maps a uid to its handle. This is a *starting point* — test with the Rules Playground.

```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    function signedIn() { return request.auth != null; }
    function myUid() { return request.auth.uid; }

    // Users: read/write only your own doc; email/fcmToken stay private.
    match /users/{uid} {
      allow read, write: if signedIn() && uid == myUid();
    }

    // Public, non-sensitive profile (handle, friendCount) — read by anyone signed in.
    match /profiles/{handle} {
      allow read: if signedIn();
      allow write: if signedIn() && request.resource.data.ownerUid == myUid();
    }

    // Friend requests: only sender can create; only receiver can accept/reject.
    match /friend_requests/{id} {
      allow read: if signedIn() &&
        (resource.data.senderUid == myUid() || resource.data.receiverUid == myUid());
      allow create: if signedIn() && request.resource.data.senderUid == myUid();
      allow update, delete: if signedIn() &&
        (resource.data.senderUid == myUid() || resource.data.receiverUid == myUid());
    }

    // Chats: only participants can read/write.
    match /chats/{chatId} {
      allow read, write: if signedIn() && myUid() in resource.data.participantsUids;
      match /messages/{msgId} {
        allow read: if signedIn() &&
          myUid() in get(/databases/$(db)/documents/chats/$(chatId)).data.participantsUids;
        allow create: if signedIn() && request.resource.data.senderUid == myUid();
        allow update, delete: if false; // messages are immutable
      }
    }

    // Communities: members read; only admin edits community doc.
    match /communities/{cid} {
      allow read: if signedIn();
      allow create: if signedIn() && request.resource.data.adminUid == myUid();
      allow update, delete: if signedIn() && resource.data.adminUid == myUid();
    }
    match /community_members/{id} {
      allow read: if signedIn();
      allow create, delete: if signedIn() && request.resource.data.userUid == myUid();
    }
    match /community_messages/{id} {
      allow read: if signedIn();
      allow create: if signedIn() && request.resource.data.authorUid == myUid();
      allow update, delete: if false;
    }

    // Blocks: only the blocker owns their block docs.
    match /blocks/{id} {
      allow read, write: if signedIn() && request.resource.data.blockerUid == myUid();
    }

    match /{document=**} { allow read, write: if false; } // deny everything else
  }
}
```

And in `firebase.json`:
```json
{
  "firestore": { "rules": "firestore.rules", "indexes": "firestore.indexes.json" },
  "storage": { "rules": "storage.rules" },
  "functions": { "source": "functions" }
}
```

---

### Files reviewed for this report
`firebase.json`, `functions/index.js`, `functions/package.json`, `lib/main.dart`, `lib/firebase_options.dart`,
`lib/services/{post_repository, friend_repository, community_repository, notification_service, telegram_storage_service, device_info_service}.dart`,
`lib/core/utils/handle_generator.dart`,
`lib/screens/auth/{device_register_screen, google_login_screen, create_handle_screen}.dart`,
`lib/screens/chat/personal_chat_screen.dart`.
Category/profile/community UI screens were pattern-sampled (not line-by-line) to conserve effort; the duplication + empty-catch findings apply across them.
