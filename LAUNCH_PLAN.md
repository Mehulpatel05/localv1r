# Launch Plan — Vadodara First, Gujarat Ready

**Date:** 2026-09-06
**Scope:** localv1 (Flutter app + FastAPI backend + Firestore + React admin)
**Companion doc:** [LOCATION_SYSTEM.md](LOCATION_SYSTEM.md) — OLX-style State → City → Area ka full technical design

---

## 1. Seedha jawab: kaun sa plan lena chahiye

Aapke paas do plan the:

| Plan | Aapka soch | Verdict |
|---|---|---|
| **A** — Sirf Vadodara launch karo, users mile to expand | Safe, focused | ✅ **Yeh karo** — go-to-market ke liye |
| **B** — Poore Gujarat ke liye banao | Bada market | ⚠️ Launch ke liye nahi, **architecture ke liye haan** |

**Meri recommendation — dono ko mila do, lekin do alag layers pe:**

> **Product/marketing = Vadodara-only. Code/database = poore Gujarat ke liye ready.**

Iska matlab:

- Aaj se hi `stateId` / `cityId` / `areaId` fields, city picker, aur city-scoped queries bana do (LOCATION_SYSTEM.md dekho).
- Lekin app me **sirf Vadodara city `enabled: true`** rakho. Baaki 30+ Gujarat cities `comingSoon: true` — picker me dikhengi, "Waitlist join karo" screen aayegi, feed nahi.
- Jab Vadodara me traction aa jaaye, ek config flag flip karo → Surat live. **Zero code change, zero migration.**

### Yeh approach kyun, Plan A ya Plan B akele kyun nahi

**Pure Plan A (Vadodara hardcode) ka nuksaan — aur yeh abhi already ho raha hai:**

Abhi codebase me `"Vadodara"` **37 jagah hardcoded** hai (`lib/` ke andar), aur inme se zyada tar sirf **display strings** hain — actual filtering kahin nahi hoti:

- [feed_screen.dart:76](lib/screens/feed/feed_screen.dart#L76) — AppBar me `'VADODARA'` badge, static text
- [create_post_screen.dart:27](lib/screens/create/create_post_screen.dart#L27) — `_cityController` ka default `'Vadodara'`, user kuch bhi type kar sakta hai
- [rooms_screen.dart:64](lib/screens/rooms/rooms_screen.dart#L64), [food_screen.dart:294](lib/screens/food/food_screen.dart#L294), [jobs_screen.dart:263](lib/screens/jobs/jobs_screen.dart#L263) — sab me `'Vadodara'` literal chipka hua hai

Sabse important baat: **`area` field database me likha jaa raha hai lekin kabhi wapas padha hi nahi jaata.** [post_repository.dart:375](lib/services/post_repository.dart#L375) `area` bhejta hai, backend [firebase_service.py:61](backend/services/firebase_service.py#L61) usse Firestore me save karta hai — lekin `_fetchPosts()` ki `Post(...)` mapping me (`post_repository.dart:118-150`) `area` field **hai hi nahi**. `Post` model me bhi koi `area` property nahi hai. Yaani location data likha jaa raha hai aur silently discard ho raha hai.

Isi wajah se [feed_screen.dart:1048](lib/screens/feed/feed_screen.dart#L1048) ka `_showAreaPicker()` ek khaali dhaancha hai — `itemCount: 0`, `final area = ''`, `onTap` ke andar kuch nahi. Area picker banaya gaya tha, kabhi wire nahi hua.

Agar aaj Vadodara hardcode karke launch kar diya, to 6 mahine baad Surat add karne ke liye ye sab karna padega: 37 strings badlo, `Post` model migrate karo, backend query rewrite karo, **aur puraane saare posts ko backfill karo** (unme `cityId` nahi hoga). Woh 2-3 hafte ka kaam hai — aur woh exactly us waqt aayega jab aap growth pe focus karna chahenge.

**Pure Plan B (poore Gujarat launch) ka nuksaan:**

Hyper-local app ka pehla din empty feed pe mar jaata hai. Vadodara ke 100 posts poore Gujarat me faila do, to har city me 3 posts. Naya user aayega, khaali feed dekhega, uninstall karega. Vadodara me hi 500 posts concentrate karo — feed bhara lagega, network effect chalu hoga.

Doosri baat, moderation. `moderation.py` + admin panel abhi ek shehar ke volume ke liye theek hai. 30 cities ka content ek hi queue me aaya to aap Gujarati, Kutchi, Hindi, English — sab me spam handle nahi kar paayenge.

---

## 2. ⚠️ Phase 0 — Location kaam se PEHLE yeh fix karo

Yeh maine code padh ke verify kiya hai. Yeh bugs **abhi live hain** aur launch ko block karte hain. City system inke upar banane ka koi fayda nahi.

### P0-1. `save_idempotent_response()` **19 jagah galat arguments** se call ho raha hai — 500 error

Function ka signature 4 parameters leta hai ([main.py:60](backend/main.py#L60)):

```python
async def save_idempotent_response(key: str, route: str, context: str, response: dict):
```

Lekin 16 call sites sirf 2 arguments bhejte hain:

```python
# main.py:804 (create_post), :914 (add_comment), :955 (vote), :987 (report),
# :1021, :1085, :1151, :1174, :1327, :1372, :1476, :1518, :1685, :1722, :1766
await save_idempotent_response(idempotency_key, res)   # ❌ TypeError
```

Sirf 3 call sites sahi hain (`:595`, `:661`, `:730` — device register/refresh/verify-phone).

**Impact:** Jaise hi koi client `Idempotency-Key` header bheje, `TypeError` uthega. Woh `global_exception_handler` ([main.py:125](backend/main.py#L125)) me jaake **500** ban jaayega — post create hone ke *baad*. Yaani post ban gaya, user ko error mila, user retry karega → **duplicate posts**. Bilkul woh cheez toot rahi hai jise rokne ke liye idempotency banayi thi.

Abhi Flutter client `Idempotency-Key` bhejta nahi, isliye chhupa hua hai. Retry logic add karte hi phat jaayega.

**Fix:** Har call site pe `route` aur `context` pass karo — `await save_idempotent_response(idempotency_key, "create_post", user_handle, res)`.

### P0-2. Delete post — client aur backend ka route match nahi karta

| Kahan | Kya |
|---|---|
| Client ([post_repository.dart:280](lib/services/post_repository.dart#L280)) | `POST /posts/{id}/delete` |
| Backend ([main.py:1026](backend/main.py#L1026)) | `DELETE /api/v1/posts/{post_id}` |

**Impact:** Delete kabhi kaam nahi karta. `405 Method Not Allowed` aata hai, aur `deletePostPermanently()` ka optimistic removal revert ho jaata hai — post UI me wapas aa jaata hai. User ko lagta hai app toota hua hai. (Iska ek hi rasta hai: user apna post delete hi nahi kar sakta — jo IT Rules 2021 compliance ke liye bhi problem hai, kyunki `grievance_center_screen.dart` 24-hour takedown ka vaada karta hai.)

**Fix:** Client ko `http.delete(...'/posts/$postId')` pe le aao.

### P0-3. Restore post — galat auth scheme

Client ([post_repository.dart:257](lib/services/post_repository.dart#L257)) `_getAuthHeaders()` bhejta hai (Firebase `Bearer` token). Backend ([main.py:992](backend/main.py#L992)) `X-Moderator-Token` header maangta hai. Hamesha fail. `hide_post` ([main.py:1443](backend/main.py#L1443)) ka bhi wahi haal.

**Fix:** Yeh dono moderator-only actions hain — inhe `PostRepository` se hata do aur admin panel me le jaao. Normal user ke repository me moderator endpoints hone hi nahi chahiye.

### P0-4. Firestore rules 4 features ko poori tarah block kar rahe hain

`firestore.rules` ka last line `match /{document=**} { allow read, write: if false; }` hai — sahi hai (deny-by-default). Problem yeh hai ki rules **jo field names maangte hain, client woh likhta hi nahi**:

| Feature | Rule kya maangta hai | Client kya likhta hai | Result |
|---|---|---|---|
| **Friendships** | *koi rule hi nahi hai* | `friendships/{id}` | 🔴 catch-all deny — friends feature poora dead |
| **Chats** | `participantsUids` ([rules:30](firestore.rules#L30)) | `participants` (handles) — [personal_chat_screen.dart:73](lib/screens/chat/personal_chat_screen.dart#L73) | 🔴 DM read/write dono deny |
| **Communities** | `adminUid` ([rules:41](firestore.rules#L41)) | `adminHandle` — [community_repository.dart:60](lib/services/community_repository.dart#L60) | 🔴 community banana deny |
| **Community members** | `userUid` ([rules:46](firestore.rules#L46)) | `userHandle` — [community_repository.dart:68](lib/services/community_repository.dart#L68) | 🔴 join deny |
| **Blocks** | `request.resource.data.blockerUid` ([rules:56](firestore.rules#L56)) | `blockerHandle` | 🔴 block/unblock deny (aur `request.resource` read pe null hota hai, isliye read bhi deny) |

Do cheezein achhi hain — `friend_requests` (`senderUid`/`receiverUid` client likhta hai, [friend_repository.dart:87](lib/services/friend_repository.dart#L87)) aur `community_messages` (`authorUid`, [community_repository.dart:128](lib/services/community_repository.dart#L128)) — yeh sahi wire hue hain. Baaki nahi.

**Fix:** Har collection pe `*Uid` fields likho (`FirebaseAuth.instance.currentUser!.uid` se), aur `friendships` ka rule likho. `blocks` rule ko read ke liye `resource.data.blockerUid` use karna chahiye, `request.resource.data` nahi.

### P0-5. Community member doc ID do jagah do tarah se banta hai

```dart
// createCommunity — community_repository.dart:67
.doc('${_currentUserHandle}_${docRef.id}')    // handle_communityId

// joinCommunity — community_repository.dart:78, isMember — :114, leaveCommunity — :92
.doc('${communityId}_$_currentUserHandle')    // communityId_handle
```

**Impact:** Community banane wala admin apni hi community me `isMember()` false paata hai, isliye `sendMessage()` ([community_repository.dart:122](lib/services/community_repository.dart#L122)) `"Must be a member to post"` throw karta hai. **Admin apni khud ki community me message nahi bhej sakta.**

**Fix:** Ek convention pakdo — `${communityId}_$handle` — aur `createCommunity` ko wahi use karao.

### P0-6. `commentCount` backend se parse hi nahi hota

`_fetchPosts()` ki `Post(...)` mapping ([post_repository.dart:118](lib/services/post_repository.dart#L118)) me `commentCount` field nahi hai, to woh default `0` reh jaata hai. Backend `commentCount` maintain karta hai ([firebase_service.py:76](backend/services/firebase_service.py#L76) set, `add_comment` me increment). Feed me har post pe **0 comments** dikhta hai chahe 50 comments hon.

**Fix:** `commentCount: d['commentCount'] ?? 0` add karo. (Yeh `area`/`cityId` add karne ke saath hi ho jaayega.)

### P0-7. `validate_text_content` do baar call ho raha hai

[main.py:769-773](backend/main.py#L769) — copy-paste. Sirf ek fizool call hai, bug nahi, lekin hatao.

### P0-8. Category filter client-side hai — category screens khaali dikhenge

`_fetchPosts()` hamesha `GET /posts?limit=20` maarta hai — **koi category param nahi**. Filter memory me hota hai ([post_repository.dart:88](lib/services/post_repository.dart#L88), aur [rooms_screen.dart:42](lib/screens/rooms/rooms_screen.dart#L42), [food_screen.dart:42](lib/screens/food/food_screen.dart#L42) me bhi).

Aur `setCategory()` ([post_repository.dart:298](lib/services/post_repository.dart#L298)) `_listenToPosts()` call karta hai — jo wahi 20 latest posts dobara laata hai. Yaani category badalne se network call hota hai lekin **result wahi 20 posts**.

**Impact:** Agar latest 20 posts me koi `rooms` post nahi hai, to Rooms screen khaali — chahe database me 200 rooms posts hon. Aur `hasMore` bhi `postsData.isNotEmpty` pe set hai ([post_repository.dart:159](lib/services/post_repository.dart#L159)) — yaani ek khaali page aane pe pagination band, lekin category filter ke baad UI ko lagta hai aur posts hain.

Yeh fix **city filter ke saath hi karo** — dono same query params hain, ek hi kaam hai. Detail LOCATION_SYSTEM.md §5 me.

---

## 3. Timeline

Assumption: ek developer, part-time. Agar full-time ho to ~40% kam.

### Phase 0 — Blockers (Week 1–2)

§2 ka poora list. City system ke liye foundation.

**Definition of done:** Do real phone pe — post banao, delete karo, comment karo, vote karo, DM bhejo, community banao aur usme message karo, friend request bhejo aur accept karo. Sab kaam kare. Firebase console me zero permission-denied errors.

### Phase 1 — Location system (Week 3–5)

LOCATION_SYSTEM.md ka full implementation:

- `lib/core/location/` — models, seed data, `LocationService`
- `Post` model + repository me `stateId`/`cityId`/`areaId`
- Backend query params + Firestore composite indexes
- City picker + area picker UI, "Change city" button
- Post create screens me city/area dropdown (free-text hatao)

**Definition of done:** Vadodara select karo → sirf Vadodara ke posts. Alkapuri select karo → sirf Alkapuri. Surat select karo → "Coming soon + waitlist". City restart ke baad yaad rahe.

### Phase 2 — Content seeding (Week 6–7, launch se pehle)

Sabse zyada ignore kiya jaane wala phase, aur sabse zyada zaroori. **Khaali app launch nahi kar sakte.**

- 8–10 areas chuno (Alkapuri, Sayajigunj, Gotri, Manjalpur, Karelibaug, Fatehgunj, Subhanpura, Waghodia Road)
- Har area me **20–30 real posts** — rooms/PG, tiffin services, local plumber-electrician, part-time jobs, weekend events
- Source: Vadodara ke Facebook groups (permission lekar), local shop owners, college notice boards
- **Har category me minimum 15 posts** — warna category tab khol ke user khaali screen dekhega

**Definition of done:** Koi bhi area + koi bhi category = minimum 5 posts.

### Phase 3 — Vadodara launch (Week 8)

- Target: MS University, Parul, Navrachana — hostel + PG demand yahin hai
- Channels: college WhatsApp groups, Vadodara Instagram pages, PG owners ke through referral
- 30-day target: **500 installs, 150 weekly-active, 50 posts/week organic**

### Phase 4 — Doosri city (Month 4–6, agar metrics mile)

Expand karne ke gates:

- ✅ 150+ weekly active in Vadodara
- ✅ 50+ posts/week organic (aapke seed ke bina)
- ✅ Day-7 retention > 20%
- ✅ Moderation queue < 24 hour lag

Agar teenon miss ho rahe hain to **expand mat karo** — Vadodara ka product theek karo. Do shehar me ek hi problem do baar hogi.

**Pehli expansion city: Surat.** Ahmedabad nahi. Surat me student + migrant worker density zyada hai, competition (Quikr/OLX/NoBroker) kam hai, aur textile + diamond industry me local job/room demand natural hai. Ahmedabad me sabhi bade players already hain — pehli expansion me unse ladna galat hai.

---

## 4. Vadodara-only phase me kya *nahi* karna

Focus ka matlab yeh bhi hai ki kuch cheezein jaan-boojh kar chhodo:

- **GPS auto-detect** — Manual city select kaafi hai. `permission_request_screen.dart` abhi location permission maangta hai; launch ke liye woh optional kar do. Permission maangna install-time pe drop-off badhata hai.
- **Multi-language UI** — Vadodara me English + Hinglish chalega. Gujarati translation Phase 4 pe.
- **Lat/long distance sorting** — Area-level filtering hi hyper-local ke liye kaafi hai. (Lekin seed data me lat/lng **daal do** — baad me chahiye hoga, aur tab se add karna migration ban jaayega.)
- **Paid listings / monetization** — Pehle supply-demand fit dhoondo.
- **iOS** — Android pe hi rehna. Gujarat me Android share ~85% hai, aur iOS build ka overhead (attestation, review) is stage pe waste hai.

---

## 5. Do lines me

**Vadodara pe launch karo, Gujarat ke liye build karo.** Do hafte P0 bugs pe kharch karo (idempotency 500s, delete route, Firestore rules jo 4 features block kar rahe hain), teen hafte OLX-style location system pe — usme city `enabled` flag ke saath, do hafte content seeding pe. Ek config flag flip karke Surat aa jaayegi jab metrics kahenge.

Sabse bada risk **tech nahi, content hai.** Location system chahe perfect ho, khaali feed pe app mar jaayega. Phase 2 mat skip karo.
