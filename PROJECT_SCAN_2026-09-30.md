# Nearhood / localv1 — Full Project Scan

**Date:** 2026-09-30
**Scanned:** `lib/` (110 Dart files, ~46,800 LOC) + `backend_v2/` (18 TS files, ~3,700 LOC) + migrations, deploy config, git state
**Method:** every claim below was read out of the code and then independently re-verified. Nothing here is taken from the older docs.

> **Pehle yeh padho:** `PROJECT_AUDIT.md`, `LAUNCH_PLAN.md`, `LOCATION_SYSTEM.md` aur `details.md` — yeh chaar docs **purane ho chuke hain**. Woh sab ek FastAPI backend (`backend/main.py`), Firestore, Google login, aur `rooms/food/jobs/community` screens ke baare mein baat karte hain. Ab in mein se **kuch bhi exist nahi karta**. Project beech mein poora rewrite hua hai. Un docs ko historical maano, current truth ke liye yeh file padho.

---

## 1. Ab actual architecture kya hai

Teen layers hain, aur beech ki layer sabse kamzor hai.

**Flutter app (`lib/`)** — 110 files. Navigation ka koi route table nahi hai; `main.dart` ka `home:` ek `AnimatedSwitcher` hai jo splash → login → `MainScreen` ke beech switch karta hai, aur baaki sab imperative `Navigator.push(MaterialPageRoute(...))` se hota hai. State management ke liye `provider` package hai lekin usme sirf **teen** cheezein registered hain (`LocationService`, `ActionStateProvider`, `UserActionStateService`); asli pattern **12+ singletons** hain (`AuthService.instance`, `BazarRepository.instance`, waghairah). Realtime ke liye koi socket nahi hai — **13 `Timer.periodic` polling loops** hain, jinme se chhe **3 second ya usse tez** chalte hain (`notification_service.dart:333` 3s, `friend_repository.dart:60` 3s, `call_listener_service.dart:30` 2s, `webrtc_call_service.dart:593` 1.5s, `incoming_call_screen.dart:124` 1.2s). Yeh Render ke free tier pe battery aur quota dono kha jaayega.

**Backend (`backend_v2/`)** — Hono framework, TypeScript. Do tarah se chal sakta hai: Cloudflare Workers (`wrangler.toml`, D1 binding) ya Node on Render (`src/server.ts`, `Dockerfile`, `render.yaml`). App production mein Render wale ko hit karta hai: `https://backend-v2-cu1p.onrender.com/api/v2`. Data Cloudflare D1 (SQLite) mein, media Cloudflare R2 mein per-user folder ke andar.

**Firebase** — sirf **push notifications** ke liye bacha hai. `firebase_core` + `firebase_messaging`, bas. `cloud_firestore`, `firebase_auth`, `firebase_storage` — teeno **pubspec mein hi nahi hain**, aur `lib/` mein ek bhi `FirebaseFirestore`/`FirebaseAuth` reference nahi hai. Auth 100% custom hai (phone OTP → opaque session token).

Iska matlab repo root pe `firestore.rules`, `firestore.indexes.json`, `storage.rules`, aur poora `functions/` folder **dead artifacts** hain. Inhe delete karo — warna agli baar koi (ya main) samjhega ki Firestore abhi bhi use ho raha hai.

### Repo state — yeh pehle fix karna padega

`backend_v2` parent repo mein **gitlink (mode 160000)** ke roop mein registered hai, lekin `.gitmodules` file **exist nahi karti**. Yaani parent repo ek commit pointer track karta hai jise resolve karne ka koi tareeka nahi hai. Aaj agar koi `localv1r.git` clone kare, use **khaali `backend_v2/` folder** milega. Backend effectively unpublished hai. Do raste hain: ya proper submodule banao (`.gitmodules` add karke), ya gitlink hatao aur backend_v2 ko parent repo mein hi normal folder banake commit karo. Main doosra recommend karta hoon — do repos maintain karne ka koi fayda nahi jab dono ek hi developer ke paas hain.

---

## 2. 🔴 Security — launch se pehle yeh sab band karo

Yeh section sabse zaroori hai. Neeche jo hai woh theoretical nahi hai, main ne code padh kar confirm kiya hai.

### S1. Auth ek header se bypass ho jaata hai — CRITICAL

`backend_v2/src/middleware/auth.ts` ki logic teen branches mein tooti hui hai:

Line 72-74 — agar request mein **koi bearer token nahi** hai lekin `x-user-handle` header hai, to middleware bas us header ko user identity maan leta hai aur `next()` call kar deta hai. Line 54-68 — agar token hai lekin `devices` table mein nahi mila, aur header hai, to woh us attacker-supplied token+handle ka **naya devices row insert kar deta hai**. Aur line 44 — agar token **valid** bhi ho, phir bhi client ka bheja hua `x-user-handle` session ke asli handle ko **override** kar deta hai, aur line 47-52 devices row ko us naye handle pe rewrite kar deta hai.

Net effect: `curl -H "x-user-handle: <kisi_ka_bhi_handle>"` se koi bhi kisi bhi user ke roop mein sab kuch kar sakta hai — uske DM padhna, uske naam se post karna, uski shop delete karna, uska account delete karna. Line 82-92 pe middleware un handles ke liye `users`/`profiles` rows **auto-create** bhi kar deta hai, to jo user exist hi nahi karta uske roop mein bhi act kar sakte ho.

**Fix:** bearer token hi single source of truth hona chahiye. `x-user-handle` header ko **poori tarah ignore karo** — woh sirf ek convenience thi jo security hole ban gayi. Token na mile to 401, bas. Client side pe `friend_repository.dart` aur `direct_chat_service.dart` jo `x-user-handle` bhejte hain unhe hatao.

### S2. OTP bypass → kisi bhi phone number ka account takeover — CRITICAL

`backend_v2/src/services/wakit_service.ts:88-101` mein `verifyOtp` in teen cases mein `true` return karta hai: `requestId` `test_otp_` ya `demo_otp_` se shuru ho, **ya** submitted code literally `123456` ya `000000` ho, **ya** `WAKIT_API_KEY` set na ho.

Problem yeh hai ki `requestId` **client ke body se aata hai** (`modules/auth/index.ts:61`) aur bina kisi validation ke `verifyOtp` ko pass ho jaata hai (`:72`). To yeh request kisi ka bhi account khol deti hai:

```
POST /api/v2/auth/verify-otp
{ "phoneNumber": "<victim ka number>", "requestId": "test_otp_1", "otp": "111111" }
```

Server isse valid maan kar line 112-131 pe ek **asli session token** mint kar dega. `123456`/`000000` wala bypass API key set hone par bhi chalta hai. Aur Cloudflare Workers deploy pe `WAKIT_API_KEY` `wrangler.toml [vars]` mein define hi nahi hai (`.env` sirf Node/Render path padhta hai), to wahan `!apiKey` branch **permanently live** hai.

**Fix:** teeno bypasses production se nikalo. Test numbers ke liye ek explicit `ENVIRONMENT !== 'production'` guard lagao. Sabse important — `requestId` server pe generate karo aur server-side store karo (phone + expiry ke saath), client ka bheja hua requestId kabhi trust na karo.

### S3. Live credentials source code mein committed hain — CRITICAL

`backend_v2/src/utils/config.ts` mein har secret ka base64-encoded fallback hardcoded hai, aur **yeh file git mein tracked hai**:

- Cloudflare account ID (32 hex chars)
- Cloudflare **API token** (`cfut_` prefix, 53 chars) — is se poore Cloudflare account pe kaam ho sakta hai
- D1 database ID (`wrangler.toml:17` pe plaintext mein bhi hai)
- R2 access key ID (32 hex) + R2 **secret access key** (64 hex) — poora media bucket
- R2 S3 endpoint URL
- JWT secret, plaintext (`wrangler.toml:9` pe bhi, saath mein `SERVER_SALT` `:11` pe)

Base64 encoding **encryption nahi hai** — woh sirf ek speed bump hai, 5 second mein decode ho jaata hai.

Aur ek aur: **`.git/config` mein ek GitHub Personal Access Token embedded hai** — `remote "project"` ka URL `https://Mehulpatel05:ghp_...@github.com/...` format mein hai.

**Fix, isi order mein:** (1) Cloudflare dashboard pe jaake API token, R2 keys **ab rotate karo** — yeh ab compromised maane jaayenge; (2) GitHub PAT revoke karo aur remote URL clean karo; (3) `config.ts` ke saare fallbacks hatao, missing env var pe crash hone do (silent fallback se better hai); (4) `wrangler.toml` se secrets nikalo, `wrangler secret put` use karo; (5) git history se secrets purge karo (`git filter-repo`) — kyunki sirf latest commit fix karne se history mein woh reh jaayenge.

### S4. `POST /auth/refresh` kuch verify nahi karta

`modules/auth/index.ts:214-222` — poora handler bas do random tokens generate karke return kar deta hai. Incoming refresh token **padha bhi nahi jaata**, aur naye access token ka hash `devices` table mein **store nahi hota**. Compare karo `:115-131` se, jahan verify-otp sahi tareeke se hash store karta hai.

Consequence interesting hai: refresh ke baad client ke paas ek aisa token hota hai jo kisi devices row mein nahi hai. Agli request pe `auth.ts:28-37` session nahi dhoondh paata, aur control `:54` pe chala jaata hai — request **sirf isliye** kaam karti hai ki client `x-user-handle` bhi bhejta hai, jo phir us bogus token ko chupke se register kar deta hai. Yaani S1 ka bug S4 ke bug ko chhupa raha hai. S1 fix karte hi refresh poori tarah tootega.

---

## 3. 🟠 Frontend aur backend ka contract match nahi karta

Client 74 distinct endpoint paths call karta hai. Backend `src/index.ts:54-64` pe sirf yeh 11 groups mount karta hai: `auth`, `profile`, `media`, `storage`, `bazar`, `chats`, `chat`, `feed`, `posts`, `friends`, `notifications`.

**Poore subsystems jinka backend mein koi route hi nahi hai** — har call 404 pe jaati hai:

| Client kya call karta hai | Kitne call sites | Kya feature marta hai |
|---|---|---|
| `/actions/counters`, `/actions/state/current`, `/actions/states`, `/actions/states/batch` | 6 | like/save/block/vote ka precomputed state — poora client-only |
| `/presence/heartbeat`, `/presence/:handle` | 3 | online/offline status, "last seen" |
| `/preferences`, `/preferences/:handle`, `/preferences/pin`, `/preferences/mute` | 6 | chat pin/mute, call privacy setting |
| `/calls/initiate`, `/calls/:id`, `/calls/:id/ice`, `/calls/:id/answer`, `/calls/:id/status`, `/calls/active`, **`wss://.../calls/:id/ws`** | 13 | **poora WebRTC voice/video calling** |
| `POST /users/fcm-token` | 2 | push token registration — yaani push notifications aate hi nahi |
| `POST /auth/profile/avatar` | 2 | avatar set/remove |
| `POST /storage/cdn-prewarm` | 1 | image prewarming |
| `POST /posts/:id/report` | 1 | post report karna |
| `POST /posts/:id/restore` | 1 | deleted post restore |
| `POST /posts/:id/comment` (singular) | 1 | **comment banana** — backend pe sirf `/comments` plural hai |
| `GET /api/v2/health` | 1 | backend health root pe `/health` serve karta hai, `/api/v2/health` nahi |

Calling wala 886-line `webrtc_call_service.dart`, 1190-line `call_screen.dart`, 472-line `incoming_call_screen.dart` — teeno backend ke bina likhe gaye hain. (Consistent hai: `main.dart:138` pe comment hai "Call system hidden for now", aur `personal_chat_screen.dart:2521` pe call buttons `actions: const []` karke hata diye gaye hain.) Yeh ~2,500 lines abhi non-functional hain.

Comment creation ka bug sabse chhota aur sabse zaroori fix hai — `post_repository.dart:401` ko `/comment` se `/comments` karo, bas. Ek line.

### Aur do confirmed backend bugs

**"My posts" kabhi nahi dikhega.** `modules/feed/index.ts:109` author filter mein `@` prepend karta hai (`author.startsWith('@') ? author : '@'+author`), lekin `:169` insert pe `@` strip karke store karta hai (`replace(/^@+/, '')`). To stored value mein kabhi `@` nahi hota aur filter hamesha `@` maangta hai — **zero rows match ho sakte hain**. Client `post_repository.dart:833` pe yeh call karta hai, aur `:841-847` pe response khaali aane par in-memory cache pe fall back karta hai. Isliye profile screen pe posts sirf usi session ke dikhte hain — cold start ya reinstall ke baad khaali, aur doosre device ke posts kabhi nahi.

**Schema drift — fresh deploy toota hua DB banayega.** `migrations/0001_initial_schema.sql` mein `feed_posts` ke sirf **9 columns** hain (id, author_handle, content, media_urls_json, audio_url, likes_count, comments_count, status, created_at). Lekin `modules/feed/index.ts:173-192` **31 columns** INSERT karta hai, `:97-110` `category`/`city_id` pe filter karta hai, `:274-307` `upvotes`/`downvotes` update karta hai. Woh missing 32 columns sirf `scripts/update_feed_schema.ts` add karta hai — aur woh script `package.json` mein **wired hi nahi hai**. Documented migration commands (`db:migrate:local` / `db:migrate:prod`) sirf `0001` chalate hain. Yaani README follow karke naya environment banaya to har post create fail hoga aur har feed read error dega. Live DB ne clearly woh script manually khaaya hai, lekin woh knowledge kahin documented nahi hai. **Fix:** `0002_feed_post_attributes.sql` banao un ALTER statements ke saath, ya `0001` ko rewrite karo.

---

## 4. 🟡 Jo features UI mein kaam karte dikhte hain par asal mein nahi

Yeh sabse dhokebaaz category hai, kyunki user ko "success" message milta hai.

`profile_screen.dart:394-423` — bio edit. `_saveBio` sirf `setState` karke `_userData!['bio']` memory mein badalta hai, dialog pop karta hai, aur "Bio saved successfully!" dikhata hai. **Koi HTTP call nahi, koi prefs write nahi.** `try` block mein kuch throw ho hi nahi sakta, to `catch` unreachable hai. Reload pe bio gayab.

`feedback_support_page.dart:55-83` — feedback submit. `await Future.delayed(600ms)` aur comment `// Simulate network request`. Phir `_isSubmitted = true`. **User ka feedback discard ho jaata hai.** Yeh sabse bura hai — user ne mehnat se likha aur use laga bhej diya.

`saved_screen.dart:43` — `_savedPosts = [];` hardcoded. Saved Posts tab **permanently khaali** hai. (Saved Items/Shops tabs asli hain, `BazarRepository` se aate hain.)

`feed_screen.dart:45-156` — filter chip pe koi real result na mile to **fake demo posts** generate hote hain: `q_sample_1/2/3` ("Any good chai stall nearby…", authors 'Ravi K.', 'Neha P.', 'Kiran S.'), `ev_sample_1`, `alt_sample_1/2/3` (ek 'Area admin' ka water-supply notice, ek missing Labrador, ek two-wheeler theft). UI mein yeh asli posts se distinguish nahi hote. **Launch se pehle nikalo** — users ko lagega app pe fake content hai.

`bazar_repository.dart:614-676` — shop insights. Backend call fail hone par error dikhane ki jagah **analytics banaa leta hai**: `dailyViews = totalViews / 7` saat dino mein baant kar, `chatsLastWeek = (totalChats * 0.7).round()`, plus hardcoded marketing "tips". `shop_insights_screen.dart` inhe asli numbers ki tarah render karta hai. Shop owner business decisions fake data pe lega.

`location_service.dart:44-46` — `setSelectedRadius(double radiusKm) { notifyListeners(); }`. **Argument poori tarah ignore hota hai**, `selectedRadiusKm` getter hardcoded `50.0` return karta hai. App ka har proximity filter permanently 50 km hai. Isi wajah se `proximity_radius_filter_bar.dart` doubly dead hai — kabhi mount nahi hota, aur hota bhi to no-op call karta.

Memory-only writes jo server tak nahi pahunchte: `post_repository.dart:862/875/889` (`markAsSold`, `toggleRecommendService`, `toggleEventRsvp`), `bazar_repository.dart:264/681/726` (`markProductAsSold`, `deleteShop`, `toggleSaveShop` — jabki `toggleSaveProduct` sahi POST karta hai, asymmetric).

Chat ke adhoore bits: `chat_list_screen.dart:880` lock feature — koi biometric/PIN gate nahi hai, bas ek `_lockedChatIds` set flip hota hai. `:921` favourite — flag save hota hai, koi UI usse filter nahi karta. `:957` "Add to list" — hardcoded tags `['Close Friends','Family','Neighbors','Work']` wala sheet, snackbar dikhata hai, **kuch save nahi karta**. `personal_chat_screen.dart:204-206` typing indicator — function ka body khaali hai, jabki `:180-201` pe 5s debounce machinery aur model mein `typing`/`typingTimestamps` fields maujood hain.

`settings_page.dart:92,96` — share text mein literally `'[Store link coming soon]'` string hai.

---

## 5. Dead code — ~1,500 lines nikal sakti hain

Zero external references (grep se confirmed): `lib/services/api_v2_service.dart` (180 lines — poori file, ek bhi caller nahi; ironically yeh "backend v2 service" hai jabki asli traffic 14 doosri files se jaata hai), `lib/core/location/gps_reverse_geocoding_engine.dart` (104 lines, `LocationEngine.detectLocation` ka duplicate), `lib/core/location/location_chip.dart`, `location_selector_field.dart`, `proximity_radius_filter_bar.dart`, `lib/features/auth/widgets/success_step.dart`, `lib/core/widgets/vote_capsule.dart`, `lib/services/device_info_service.dart`, `FakeAuthRepository` (`auth_repository.dart:32-61`), `_DummyRepo` (`other_user_profile_sheet.dart:49`).

Sirf "Cancel Setup → Sign Out" path se reachable purana duplicate login stack: `screens/auth/phone_login_screen.dart` (284) + `screens/auth/otp_verify_screen.dart` (434). Live flow `features/auth/login_flow_page.dart` hai.

`TokenDecisionEngine.instance` (`token_decision_engine.dart:15-23`) — **kabhi populate nahi hota**. `AuthService` apna private `_decisionEngine` field use karta hai (`auth_service.dart:34`, update `:558`). Jo bhi UI static accessor padhega use hamesha anonymous/guest dikhega.

Firestore-era artifacts: `firestore.rules`, `firestore.indexes.json`, `storage.rules`, `functions/`. Root pe bikhre helper scripts: `check_fs.py`, `fix_backend.py`, `fix_frontend.py`, `fix_ui.py`, `generate_app_logic_doc.py`, `downloaded_js.txt`.

---

## 6. Architectural cheezein jo baad mein dard dengi

**Koi shared HTTP layer nahi hai.** `http` package hai, aur har service apna transport khud likhta hai. Auth header **6+ tareeke** se inject hota hai: `_getHeaders()` (`api_v2_service.dart:18`), `_getAuthHeaders()` (`post_repository.dart:518`), ek aur `_getAuthHeaders()` (`friend_repository.dart`, jo `x-user-handle` aur redundant `user-handle` dono bhejta hai), aur `bazar_repository.dart` mein ~20 jagah inline `{'Authorization': 'Bearer $token'}` literals. Timeouts 0 se 15 second tak — koi standard nahi. **401-refresh-and-retry sirf 2 jagah hai** (`post_repository.dart:766-777` vote, `auth_service.dart:408-413` deleteAccount) — baaki ~90 call sites bas fail ho jaate hain.

Teen requests bilkul **unauthenticated** jaati hain: `post_repository.dart:512-516` ka `_getHeaders()` mein auth header hi nahi hai (aur woh `GET /posts/{id}/comments` ke liye use hota hai), `GET /posts?cityId=` sirf `{'Accept-Encoding': 'gzip'}` bhejta hai (`:137`), aur `GET /bazar/listings` koi header nahi bhejta (`bazar_repository.dart:115`).

Yeh sab ek hi kaam ka 6 versions hai. Ek `ApiClient` class banao jo base URL, auth header, timeout, 401 refresh, aur error mapping ek jagah handle kare — phir 14 services usse use karein. Is refactor ke baad `/actions`/`/presence`/`/calls` type endpoints add karna trivial ho jaayega.

**Do competing state systems.** `ActionStateProvider` (`core/action_state/`) aur `UserActionStateService` (`services/`) — like/save/block/vote ke **do independent implementations**, dono `main.dart` ke same Provider tree mein registered, dono ke paas `isLiked/isSaved/isBlocked`, dono overlapping `/actions/states` endpoints hit karte hain. Yeh aapas mein disagree kar sakte hain. `TokenDecisionEngine.canCallUserSync` ek se padhta hai, feed widgets doosre se. Ek chuno, doosra delete karo.

**`PostRepository` Provider mein registered nahi hai** lekin 5 jagah `context.read<PostRepository>()` call hota hai (`friends_screen.dart:812,999,1013,1161` aur `discover_people_screen.dart:187`). Yeh runtime pe `ProviderNotFoundException` throw karega. Baaki jagah woh constructor se pass hota hai (`MainScreen(repository: ...)`) — do idioms mix ho gaye hain.

**Config duplication.** `ApiConstants.baseUrl` `--dart-define=BACKEND_URL` support karta hai, lekin do jagah production host hardcoded hai jo usse bypass kar deti hai: `api_v2_service.dart:16` (dead file, so moot) aur — yeh important hai — `app_image_cache_service.dart:53-60`, jahan har `.r2.dev/` URL ko hardcoded `backend-v2-cu1p.onrender.com` pe rewrite kiya jaata hai. Yaani staging build pe bhi **saara image traffic production pe** jaayega. Aur `api_constants.dart:15` pe `rootUrl` `/api/v1` strip karne ki koshish karta hai jabki `baseUrl` `/api/v2` pe khatam hota hai — v1→v2 migration ka leftover, `replaceAll` no-op hai.

**Theme dark-only hai par pretend nahi karta.** `theme.dart:50-51` pe `NearhoodColors.light == NearhoodColors.dark == darkTealScheme`, aur `:143-144` pe `lightTheme == darkTheme`. Phir bhi `main.dart:167` pe `themeMode: ThemeMode.system` set hai — woh decorative hai. Koi text-style scale define nahi hai; sizes/weights call sites pe hardcoded hain. Aur `main_screen.dart` theme tokens bypass karke `Colors.black`, `Color(0xFF072E33)`, `Color(0xFF90B4B6)` inline likhta hai — usme `#0E525B` bhi hai jo token set mein hi nahi hai.

`lib/core/motion.dart` — **yeh file sabse achhi likhi hui hai** poore repo mein. Durations (100/180/220/280/240ms), curves (`easeOutCubic` in, `easeInCubic` out), distances (8/12/16), aur `isReduceMotion` + `getDuration(context, base)` accessibility helpers. Problem sirf yeh hai ki inhe **use nahi kiya jaata**: `main_screen.dart:125,227` raw constant `AppMotion.durationMicro` use karta hai instead of `AppMotion.micro(context)`, aur `main.dart:171-173` plus `_ProfileNavAvatar` (`main_screen.dart:317-321`) 450ms/150ms/200ms aur curves token system ke bahar hardcode karte hain. Reduce-motion setting wale users ko animations dikhti rahengi.

**Ek confirmed UI bug:** `_ProfileNavAvatar` (`main_screen.dart:287,297-339`) `const` hai aur `_currentIndexNotifier.value` **listen kiye bina** padhta hai, plus `context.findAncestorStateOfType` se doosre State ke private members mein ghusta hai. Isliye bottom nav ka profile tab **kabhi selected state nahi dikhata**. Baaki teen items sahi hain — woh `currentIndex` parameter se lete hain.

**File sizes.** `personal_chat_screen.dart` **3,541 lines**, `chat_list_screen.dart` 2,747, `register_shop_screen.dart` 1,780, `feed_screen.dart` 1,762. Aur do models screen files ke andar define hain — `BazarProduct` (`bazar_screen.dart:11`) aur `LocalShop` (`shop_detail_screen.dart:9-31`) — jo `lib/models/` mein hone chahiye.

**PII plaintext mein.** Tokens sahi jagah hain (`flutter_secure_storage`), lekin `auth_service.dart:159-164` `user_handle`, `user_id`, aur **`phone_number`** ko `SharedPreferences` mein mirror karta hai "instant 0ms UI access" ke liye. SharedPreferences plaintext hai. Phone number wahan se hatao.

**Token expiry check nahi hota.** `TokenClaims.isExpired` (`token_claims.dart:64`) `exp == null` hone par **`false`** return karta hai — yaani claim-less token permanently valid padha jaata hai. Aur `SplashController._resolveAuthSession` (`splash_controller.dart:166-200`) restore pe expiry **check hi nahi karta**, to expired JWT bhi `isLoggedIn: true` deta hai; app `MainScreen` mein ghus jaata hai aur phir request-by-request fail hota hai. Uske fallback branch mein `prefs.getString('is_logged_in')` hai — woh key **kahin likhi hi nahi jaati**, permanently dead.

Ek aur: `auth_service.dart:133` pe refresh token **access token pe fall back** karta hai agar server refresh token na bheje. Phir refresh endpoint ko access token ke saath call kiya jaayega.

---

## 7. Mera suggested order

Yeh sequence isliye hai ki har step ka foundation pichhle step pe hai.

**Phase 0 — aaj (security, code se pehle).** Cloudflare API token aur R2 keys rotate karo. GitHub PAT revoke karo, `.git/config` clean karo. Yeh do kaam code change nahi hain, dashboard pe hone wale hain, isliye pehle.

**Phase 1 — auth theek karo.** `x-user-handle` trust hatao (S1), OTP bypasses band karo aur `requestId` server-side banao (S2), `/auth/refresh` ko asli refresh token validate karana aur naya hash store karana sikhao (S4), `config.ts` se hardcoded fallbacks nikalo aur `wrangler.toml` se secrets hatao (S3), phir git history purge. Yeh sab ek hi PR hai — inhe alag karne ka matlab nahi, kyunki S4 ka fix S1 ke bina tootega.

**Phase 2 — data layer sach bolna shuru kare.** `0002` migration likho feed_posts ke 32 columns ke liye. Author filter ka `@` mismatch fix karo. `/comment` → `/comments` (one-liner). Feed ke fake demo posts nikalo. Bazar insights ka fabricated fallback hatao — error dikhao. Bio save aur feedback submit ko asli endpoints do (ya UI se hatao jab tak endpoint na ho — fake success se better hai).

**Phase 3 — shared `ApiClient`.** Ek transport layer, ek auth injection, ek timeout policy, ek 401-refresh. 14 services usse migrate karo. Iske baad hi missing subsystems add karna sensible hai.

**Phase 4 — subsystems ka faisla.** `/actions`, `/presence`, `/preferences` backend pe implement karo ya client se nikalo. Calling ke liye decide karo: backend banao ya woh 2,500 lines archive karo. 13 polling loops ko kam karo — 3s polls ko 15-30s karo ya server-sent events/WebSocket socho.

**Phase 5 — motion/polish.** Yeh woh kaam hai jo pehle discuss hua tha. Isse **ab nahi** karna chahiye: `AppMotion` tokens already sahi define hain, unka use consistent karna chhota kaam hai, lekin jab tak app pe 6 timers 3-second pe HTTP maar rahe hain, jank ka asli cause woh hai, animation curves nahi. Phase 4 ke polling reduction ke baad `--profile` mode mein measure karo, phir motion tune karo.

---

## 8. Jo main confirm nahi kar saka

Live backend probe nahi kar paaya — is sandbox ka network egress `backend-v2-cu1p.onrender.com` ko block karta hai. To yeh do cheezein aapko khud verify karni hongi: (1) live D1 database mein `feed_posts` ke woh 32 extra columns actually hain ya nahi (`scripts/update_feed_schema.ts` chalaya gaya tha ya nahi) — `PRAGMA table_info(feed_posts)` chala ke dekho; (2) Render pe deployed code current `47600be` commit hai ya purana.

Deployment ambiguity bhi hai: `wrangler.toml` Cloudflare Workers ke liye configured hai, `Dockerfile`+`render.yaml` Render ke liye, aur `package.json` mein `deploy:cloudflare` script hai. App Render URL hit karta hai. Dono jagah deployed hai ya sirf Render pe — yeh mujhe code se pata nahi chala, aur yeh maayne rakhta hai kyunki `WAKIT_API_KEY` sirf `.env` (Render) mein hai, `wrangler.toml [vars]` (Workers) mein nahi — to Workers pe OTP verification permanently bypass mode mein chalega.
