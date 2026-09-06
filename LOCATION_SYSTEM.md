# Location System — OLX-Style State → City → Area

**Date:** 2026-09-06
**Companion doc:** [LAUNCH_PLAN.md](LAUNCH_PLAN.md) — kaun sa plan, timeline, aur Phase 0 blockers
**Prerequisite:** LAUNCH_PLAN.md §2 ke saare P0 bugs pehle fix karo. Location system unke upar banega.

---

## 1. Aaj kya haalat hai

Aapne jo maanga — "OLX jaisa perfect state, city, aur us city ke andar ke areas, user city select kare to us city ka data dikhe, aur doosri city me jaane ka button ho" — abhi uska **koi hissa kaam nahi karta**. Sirf khaali dhaanche aur display strings hain.

| Cheez | Status | Kahan |
|---|---|---|
| State list | ❌ Nahi hai | — |
| City list | ❌ Nahi hai — user free-text type karta hai | [create_post_screen.dart:328](lib/screens/create/create_post_screen.dart#L328) `hint: 'City'` |
| Area list | ❌ Nahi hai — free-text | [create_post_screen.dart:320](lib/screens/create/create_post_screen.dart#L320) `hint: 'Local Area'` |
| Area picker UI | 🟡 Khaali dhaancha | [feed_screen.dart:1048](lib/screens/feed/feed_screen.dart#L1048) — `itemCount: 0`, `final area = ''`, `onTap` khaali |
| Selected city state | ❌ Nahi hai | `PostRepository` me koi city field nahi |
| City-wise filtering | ❌ Nahi hai | Backend `GET /posts` sirf `author` + `cursor` leta hai ([main.py:809](backend/main.py#L809)) |
| "Change city" button | ❌ Nahi hai | — |
| `area` field | 🟡 **Likha jaata hai, padha nahi jaata** | Neeche dekho |

### Woh sabse badi baat — `area` silently gum ho raha hai

Yeh data flow trace kiya:

1. **Client bhejta hai** — [create_post_screen.dart:112](lib/screens/create/create_post_screen.dart#L112):
   ```dart
   area: '${_areaController.text.trim()}, ${_cityController.text.trim()}',
   ```
   Do free-text fields ko comma se jod kar ek string. `"Alkapuri, Vadodara"`. Koi validation nahi — user `"asdf, xyz"` bhi bhej sakta hai.

2. **Repository forward karta hai** — [post_repository.dart:375](lib/services/post_repository.dart#L375): `if (area != null) 'area': area,`

3. **Backend accept karta hai** — [main.py:494](backend/main.py#L494): `area: Optional[str] = None`

4. **Firestore me save hota hai** — [firebase_service.py:61](backend/services/firebase_service.py#L61): `"area": area,`

5. **Backend wapas bhejta hai** — `GET /posts` poora doc return karta hai, to `area` response me **hai**.

6. **Aur yahan gum ho jaata hai** — [post_repository.dart:118-150](lib/services/post_repository.dart#L118) ki `Post(...)` mapping me 27 fields map hote hain (`roomTitle`, `foodRating`, `jobCompany`, sab kuch) lekin **`area` nahi**. `Post` model me ([post_model.dart](lib/models/post_model.dart)) `area` property hai hi nahi — `roomArea` hai, jo alag cheez hai.

Yaani: location data likha jaa raha hai, network pe travel kar raha hai, aur client pe pahunchte hi discard ho raha hai. Isi wajah se feed me har post pe hardcoded `'Vadodara'` dikhta hai ([feed_screen.dart:910](lib/screens/feed/feed_screen.dart#L910)) — kyunki asli data available hi nahi hai.

Ek achhi khabar: chunki `area` kabhi read nahi hua, koi feature uspe depend nahi karta. Isliye **schema todne ka risk zero hai** — aap `area` string ko structured IDs se replace kar sakte ho bina kuch todne ke.

---

## 2. Design: teen level, IDs pe based

OLX ka model exactly yeh hai:

```
State (Gujarat)
  └── City (Vadodara)
        └── Area (Alkapuri, Sayajigunj, Gotri, Manjalpur, ...)
```

**Sabse zaroori decision: string ki jagah stable IDs use karo.**

```dart
stateId: 'GJ'
cityId:  'GJ-VAD'
areaId:  'GJ-VAD-ALKAPURI'
```

Kyun IDs, display names nahi:

- Display name badal sakta hai ("Vadodara" vs "Baroda" — dono chalte hain). ID kabhi nahi badalti.
- Gujarati translation baad me add karna ho to sirf label badlo, data nahi.
- Firestore `==` query pe ID exact match deti hai. String pe `"Alkapuri, Vadodara"` vs `"alkapuri,vadodara"` vs `"Alkapuri , Vadodara"` — sab alag documents ban jaayenge.
- Areas ki spelling users galat likhenge. Dropdown se ID aayegi to consistency guarantee.

Aur **`areaId` ke andar `cityId` embed karo** (`GJ-VAD-ALKAPURI`). Isse do fayde: debugging me turant pata chal jaata hai post kahan ka hai, aur backend `areaId.startsWith(cityId)` se sanity check kar sakta hai — cross-city injection nahi ho payegi.

### Data model

`lib/core/location/location_models.dart`:

```dart
class GeoState {
  final String id;        // 'GJ'
  final String name;      // 'Gujarat'
  final List<GeoCity> cities;
  const GeoState({required this.id, required this.name, required this.cities});
}

class GeoCity {
  final String id;        // 'GJ-VAD'
  final String stateId;   // 'GJ'
  final String name;      // 'Vadodara'
  final bool enabled;     // ⭐ launch control — sirf Vadodara true
  final List<GeoArea> areas;
  final double? lat;      // future distance sorting ke liye — abhi use nahi
  final double? lng;
  const GeoCity({
    required this.id, required this.stateId, required this.name,
    this.enabled = false, required this.areas, this.lat, this.lng,
  });
}

class GeoArea {
  final String id;        // 'GJ-VAD-ALKAPURI'
  final String cityId;    // 'GJ-VAD'
  final String name;      // 'Alkapuri'
  final String? pincode;  // '390007'
  final double? lat;
  final double? lng;
  const GeoArea({
    required this.id, required this.cityId, required this.name,
    this.pincode, this.lat, this.lng,
  });
}
```

`enabled` flag hi poora launch strategy control karta hai. LAUNCH_PLAN.md ka "Vadodara pe launch, Gujarat ke liye build" — technically **yeh ek boolean hai**.

**lat/lng abhi bharo chahe use na karo.** Distance sorting Phase 4+ ka kaam hai, lekin coordinates seed data me daal dena free hai. Baad me add karna migration ban jaayega.

### Seed data kahan rakho

`lib/core/location/gujarat_data.dart` — hardcoded Dart const. Firestore me nahi.

Kyun hardcoded:
- Zero network call, zero latency — app khulte hi picker ready
- Offline kaam karta hai
- Firestore read cost zero (ek read/user/session bachta hai — 500 users pe roz 500 reads)
- Version control me diff dikhta hai — kaun sa area kab add hua

Trade-off: naya area add karne ke liye app update chahiye. Launch phase me yeh acceptable hai — areas hafte-hafte nahi badalte. Agar baad me dynamic chahiye, to Firestore me `location_config` doc rakho aur hardcoded ko fallback banao. **Abhi over-engineer mat karo.**

```dart
const kGujarat = GeoState(
  id: 'GJ',
  name: 'Gujarat',
  cities: [
    GeoCity(
      id: 'GJ-VAD', stateId: 'GJ', name: 'Vadodara',
      enabled: true,                      // ⭐ sirf yeh live
      lat: 22.3072, lng: 73.1812,
      areas: [
        GeoArea(id: 'GJ-VAD-ALKAPURI',   cityId: 'GJ-VAD', name: 'Alkapuri',    pincode: '390007'),
        GeoArea(id: 'GJ-VAD-SAYAJIGUNJ', cityId: 'GJ-VAD', name: 'Sayajigunj',  pincode: '390005'),
        GeoArea(id: 'GJ-VAD-GOTRI',      cityId: 'GJ-VAD', name: 'Gotri',       pincode: '390021'),
        GeoArea(id: 'GJ-VAD-MANJALPUR',  cityId: 'GJ-VAD', name: 'Manjalpur',   pincode: '390011'),
        GeoArea(id: 'GJ-VAD-KARELIBAUG', cityId: 'GJ-VAD', name: 'Karelibaug',  pincode: '390018'),
        GeoArea(id: 'GJ-VAD-FATEHGUNJ',  cityId: 'GJ-VAD', name: 'Fatehgunj',   pincode: '390002'),
        GeoArea(id: 'GJ-VAD-SUBHANPURA', cityId: 'GJ-VAD', name: 'Subhanpura',  pincode: '390023'),
        GeoArea(id: 'GJ-VAD-WAGHODIA',   cityId: 'GJ-VAD', name: 'Waghodia Road', pincode: '390019'),
        // ~20 areas total. Neeche §8 me full list.
      ],
    ),
    GeoCity(id: 'GJ-SRT', stateId: 'GJ', name: 'Surat',      enabled: false, areas: [...]),
    GeoCity(id: 'GJ-AMD', stateId: 'GJ', name: 'Ahmedabad',  enabled: false, areas: [...]),
    GeoCity(id: 'GJ-RJT', stateId: 'GJ', name: 'Rajkot',     enabled: false, areas: [...]),
    // Bhavnagar, Jamnagar, Gandhinagar, Anand, Bharuch, Junagadh, Nadiad...
  ],
);

const kStates = [kGujarat];   // baad me: Maharashtra, Rajasthan
```

**Note `kStates` list:** Aaj sirf Gujarat hai. Lekin state ko top-level rakhne ka matlab yeh hai ki Maharashtra add karna bhi sirf ek list entry hai — model change nahi. Yeh aapke "poore Gujarat" plan se bhi aage ka rasta khula rakhta hai.

---

## 3. `LocationService` — selected city ko yaad rakho

`lib/core/location/location_service.dart`:

```dart
class LocationService extends ChangeNotifier {
  static const _kCityKey = 'selected_city_id';
  static const _kAreaKey = 'selected_area_id';
  static const _kDefaultCityId = 'GJ-VAD';

  GeoCity _city = _lookupCity(_kDefaultCityId)!;
  GeoArea? _area;   // null = poori city

  GeoCity get city => _city;
  GeoArea? get area => _area;
  String get cityId => _city.id;
  String? get areaId => _area?.id;

  /// UI header ke liye: "Alkapuri, Vadodara" ya "Vadodara"
  String get displayLabel => _area == null ? _city.name : '${_area!.name}, ${_city.name}';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCity = _lookupCity(prefs.getString(_kCityKey) ?? _kDefaultCityId);
    // Purani saved city agar disable ho gayi ho to default pe wapas
    _city = (savedCity != null && savedCity.enabled) ? savedCity : _lookupCity(_kDefaultCityId)!;
    final savedAreaId = prefs.getString(_kAreaKey);
    // Area sirf tab valid hai jab woh isi city ka ho
    _area = _city.areas.where((a) => a.id == savedAreaId).firstOrNull;
    notifyListeners();
  }

  Future<void> setCity(GeoCity c) async {
    if (!c.enabled) return;      // guard — disabled city select nahi ho sakti
    _city = c;
    _area = null;                // ⚠️ city badli to area reset — warna Surat me Alkapuri filter reh jaayega
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCityKey, c.id);
    await prefs.remove(_kAreaKey);
    notifyListeners();
  }

  Future<void> setArea(GeoArea? a) async {
    if (a != null && a.cityId != _city.id) return;   // cross-city area guard
    _area = a;
    final prefs = await SharedPreferences.getInstance();
    a == null ? await prefs.remove(_kAreaKey) : await prefs.setString(_kAreaKey, a.id);
    notifyListeners();
  }
}
```

Teen defensive baatein jo silent bugs rokti hain:

1. **`setCity` me area reset** — warna user Vadodara/Alkapuri se Surat pe jaayega aur `areaId=GJ-VAD-ALKAPURI` filter Surat ki query me chala jaayega. Result: hamesha khaali feed, koi error nahi. Debug karna mushkil.
2. **`load()` me `enabled` check** — agar kabhi koi city disable karni pade (spam attack, ya expansion rollback), to us city ke existing users default pe aa jaayenge, khaali screen pe atkenge nahi.
3. **`setArea` me `cityId` match** — deep link ya restore se galat area aane pa guard.

`main.dart` me `PostRepository` ke saath banao:

```dart
// main.dart:47 ke paas
locationService = LocationService();
postRepository = PostRepository(locationService);   // repo location ko sunta hai
await locationService.load();
```

`PostRepository` `LocationService` ko listen karega — city ya area badle to feed automatically refetch ho. Aapke existing `ChangeNotifier` pattern se yeh natural fit hai.

---

## 4. `Post` model + repository me location

**`Post` model** ([post_model.dart](lib/models/post_model.dart)) me teen field add karo:

```dart
final String? stateId;
final String? cityId;
final String? areaId;
final String? areaName;   // denormalized display label — read pe lookup bachata hai
```

`areaName` isliye ki feed card render karte waqt har post pe `kGujarat` traverse karna padega. Ek chhota denormalized string sasta hai.

Purane posts me yeh sab `null` honge — isliye **nullable rakho**. `Post.fromJson` aur `toJson` dono me add karo (dono me `roomArea` ke paas, taaki confusion na ho — `roomArea` ek alag legacy field hai).

**`_fetchPosts()` ki mapping** ([post_repository.dart:118](lib/services/post_repository.dart#L118)) me — yahan **P0-6 ka `commentCount` bhi saath fix ho jaayega**:

```dart
final newPosts = postsData.map((d) => Post(
  id: d['id'],
  authorHandle: d['authorHandle'] ?? 'Anon',
  // ...existing 27 fields...
  commentCount: d['commentCount'] ?? 0,     // ⭐ P0-6 fix — ab tak 0 dikhta tha
  stateId: d['stateId'] as String?,
  cityId: d['cityId'] as String?,
  areaId: d['areaId'] as String?,
  areaName: d['areaName'] as String?,
)).toList();
```

**`addPost()`** ([post_repository.dart:315](lib/services/post_repository.dart#L315)) me purana `area` string param hatao, IDs lo:

```dart
Future<void> addPost({
  required String authorHandle,
  required String content,
  required PostCategory category,
  required String cityId,        // ⭐ required — optional rakha to screens skip kar denge
  required String areaId,
  // area: String?  ← yeh hata do
  ...
})
```

`required` rakhna zaroori hai. Optional rakha to koi na koi post screen (7 hain) usse pass karna bhool jaayega, aur woh post feed me kabhi nahi dikhega — bina kisi error ke. Compiler se check karwa lo.

---

## 5. Backend: query params + indexes

`GET /api/v1/posts` ([main.py:809](backend/main.py#L809)) abhi sirf `limit`, `cursor`, `author` leta hai. Add karo:

```python
@app.get("/api/v1/posts")
async def get_posts(
    limit: int = 20,
    cursor: Optional[str] = None,
    author: Optional[str] = None,
    cityId: Optional[str] = None,
    areaId: Optional[str] = None,
    category: Optional[str] = None,      # ⭐ P0-8 fix — saath me hi
    authorization: Optional[str] = Header(None),
):
    query = db.collection("posts")
    if author:   query = query.where("authorHandle", "==", author)
    if cityId:   query = query.where("cityId", "==", cityId)
    if areaId:   query = query.where("areaId", "==", areaId)
    if category: query = query.where("category", "==", category)
    query = query.order_by("createdAt", direction=firestore.Query.DESCENDING).limit(min(limit, 50))
```

**`category` param isi PR me karo.** LAUNCH_PLAN.md P0-8 me likha hai ki category filter abhi client-side hai, isliye Rooms screen khaali dikh sakta hai. Woh aur city filter — dono same query hai, ek hi kaam. Alag-alag karne se dobara indexes banane padenge.

`PostCreateRequest` ([main.py:490](backend/main.py#L490)) me:

```python
class PostCreateRequest(BaseModel):
    content: str = Field(..., min_length=1, max_length=5000)
    category: PostCategory
    cityId: str = Field(..., pattern=r"^[A-Z]{2}-[A-Z]{3}$")
    areaId: str = Field(..., pattern=r"^[A-Z]{2}-[A-Z]{3}-[A-Z0-9_]+$")
    # area: Optional[str]  ← hata do
```

Pattern validation regex se laga do — garbage IDs database me nahi ghusengi. Aur ek server-side check add karo:

```python
if not request.areaId.startswith(request.cityId + "-"):
    raise HTTPException(400, "areaId does not belong to cityId")
```

Yeh isliye ki client trusted nahi hai (`details.md` ka "Zero-Trust Client" principle — modified APK galat combination bhej sakta hai). Ek line me cross-city injection band.

`stateId` ko `cityId` se derive karo (`cityId.split("-")[0]`) — client se mat lo, ek kam field validate karni padegi.

### ⚠️ Firestore composite indexes — yeh miss karna sabse aasaan galti hai

Firestore me `where` + `order_by` ke har combination ko **explicit composite index** chahiye. Bina index, query **runtime pe fail hoti hai** — deploy ke waqt nahi. Yaani local pe theek lagega, production me feed khaali.

`firestore.indexes.json` me abhi 3 indexes hain — `category+createdAt`, `authorHandle+createdAt`, `messages`. Naye chahiye:

```json
{ "collectionGroup": "posts", "queryScope": "COLLECTION", "fields": [
  { "fieldPath": "cityId", "order": "ASCENDING" },
  { "fieldPath": "createdAt", "order": "DESCENDING" } ] },

{ "collectionGroup": "posts", "queryScope": "COLLECTION", "fields": [
  { "fieldPath": "cityId", "order": "ASCENDING" },
  { "fieldPath": "category", "order": "ASCENDING" },
  { "fieldPath": "createdAt", "order": "DESCENDING" } ] },

{ "collectionGroup": "posts", "queryScope": "COLLECTION", "fields": [
  { "fieldPath": "areaId", "order": "ASCENDING" },
  { "fieldPath": "createdAt", "order": "DESCENDING" } ] },

{ "collectionGroup": "posts", "queryScope": "COLLECTION", "fields": [
  { "fieldPath": "areaId", "order": "ASCENDING" },
  { "fieldPath": "category", "order": "ASCENDING" },
  { "fieldPath": "createdAt", "order": "DESCENDING" } ] }
```

`firebase deploy --only firestore:indexes` chalao aur console me **"Enabled" status ka wait karo** — building me 5-10 minute lagte hain. Us beech queries fail hongi.

Ek aur baat: Firestore me equality filters ka **order matter nahi karta**, lekin fields ka set matter karta hai. `cityId + category + createdAt` index `cityId + createdAt` query ko cover **nahi** karta. Isliye chaaron alag chahiye.

---

## 5b. Feed tab (`trending`) ka gotcha

`FeedTab.trending` abhi client-side sort hai ([post_repository.dart:78](lib/services/post_repository.dart#L78)) — jo 20 posts aaye, unhi ko `score` se sort karta hai. City filter add karne ke baad bhi yeh **"20 latest posts ka trending"** rahega, "city ka trending" nahi.

Launch ke liye acceptable hai. Lekin jaan lo ki proper fix ke liye `score` pe `order_by` chahiye hoga, aur `cityId + score` ka naya index. Post-launch pe rakho — abhi scope badhana nahi.

---

## 6. UI: city picker, area picker, "Change city" button

### Feed header

[feed_screen.dart:76](lib/screens/feed/feed_screen.dart#L76) ka static `'VADODARA'` badge → tappable location chip:

```
┌────────────────────────────────────────────┐
│  📍 Alkapuri, Vadodara  ▾      👥  🔔  ⋮  │
└────────────────────────────────────────────┘
```

Tap → bottom sheet:

```
┌────────────────────────────────────────────┐
│  Your location                             │
│                                            │
│  📍 Vadodara                               │
│     Gujarat                    [Change ▸]  │  ← city change button
│  ─────────────────────────────────────────  │
│  AREA                                      │
│  ○ All of Vadodara            (default)    │
│  ● Alkapuri                                │
│  ○ Sayajigunj                              │
│  ○ Gotri                                   │
│  ○ Manjalpur                               │
│  ...                                       │
└────────────────────────────────────────────┘
```

"Change ▸" → city picker screen. Yeh do-level nesting OLX se hi liya hai: area roz-roz badalta hai (isliye ek tap door), city kabhi-kabhaar (isliye ek extra screen).

### City picker screen

```
┌────────────────────────────────────────────┐
│  ←  Select city                            │
│  ┌──────────────────────────────────────┐  │
│  │ 🔍 Search city...                    │  │
│  └──────────────────────────────────────┘  │
│                                            │
│  GUJARAT                                   │
│  ✓ Vadodara                                │
│    Surat                     Coming soon   │  ← greyed, tap = waitlist
│    Ahmedabad                 Coming soon   │
│    Rajkot                    Coming soon   │
└────────────────────────────────────────────┘
```

`enabled: false` cities ko **dikhao, chhupao nahi.** Do wajah:

1. User ko pata chalta hai app grow kar raha hai — "sirf Vadodara ka app" nahi lagta
2. Waitlist tap se aapko demand signal milta hai — Phase 4 me kaun si city pehle karni hai, yeh **data se** decide hoga, andaaze se nahi

Waitlist tap pe Firestore `city_waitlist` collection me `{cityId, uid, createdAt}` likho. Ek naya rule chahiye hoga (`allow create: if signedIn()`, read `false`).

**States ko section header banao** (`GUJARAT`), separate screen nahi. Aaj ek hi state hai — do-step navigation faltu friction hai. Jab doosra state aayega, header list apne aap kaam karegi.

### Post create screens — free-text hatao

7 screens me free-text city/area fields hain:

| Screen | Line |
|---|---|
| create_post_screen.dart | [:319-330](lib/screens/create/create_post_screen.dart#L319) |
| room_post_screen.dart | [:286](lib/screens/rooms/room_post_screen.dart#L286) |
| shop_post_screen.dart | [:282](lib/screens/shop/shop_post_screen.dart#L282) |
| food_post_screen.dart | [:292](lib/screens/food/food_post_screen.dart#L292) |
| events_post_screen.dart | [:305](lib/screens/events/events_post_screen.dart#L305) |
| jobs_post_screen.dart | [:313](lib/screens/jobs/jobs_post_screen.dart#L313) |
| services_post_screen.dart | [:310](lib/screens/services/services_post_screen.dart#L310) |

Saaton me ek hi shared widget lagao — `LocationSelectorField`:

- City = `LocationService.city` se pre-filled, read-only (jo city dekh rahe ho, wahin post karo — OLX bhi aisa karta hai)
- Area = dropdown, required
- `TextEditingController` wale free-text fields poori tarah hatao

Ek shared widget banao, saat jagah copy-paste **mat** karo. `fix_ui.py` jaisi regex scripts isi wajah se banani padi thi — duplicated UI code. Ek widget = ek jagah fix.

---

## 7. Migration: purane posts ka kya

Aaj database me jo posts hain unme `cityId` nahi hai. Woh city-filtered query me **kabhi nahi aayenge**.

Aapke case me yeh actually **problem nahi hai** — abhi jo posts hain woh test/demo data hai (`post_repository.dart:154` me comment: *"Demo posts removed for production"*). Launch se pehle sab wipe kar do.

Lekin agar kuch posts bachane hain, ek chhoti backfill script chalao:

```python
# scripts/backfill_city.py — ek baar chalao, phir delete
for doc in db.collection("posts").stream():
    d = doc.to_dict()
    if d.get("cityId"):
        continue
    # purani "area" string thi: "Alkapuri, Vadodara"
    area_str = (d.get("area") or "").split(",")[0].strip()
    area_id = AREA_NAME_TO_ID.get(area_str.upper())   # gujarat_data se generate
    doc.reference.update({
        "cityId": "GJ-VAD",
        "stateId": "GJ",
        "areaId": area_id or "GJ-VAD-OTHER",   # match na ho to fallback
        "areaName": area_str or "Vadodara",
    })
```

`GJ-VAD-OTHER` ek asli area rakho `gujarat_data.dart` me — "Other / Not listed". Yeh do kaam karta hai: backfill ka fallback banta hai, aur naye users ko bhi option deta hai jab unka area list me na ho. Aur woh ID monitor karo — agar 20% posts `OTHER` me ja rahe hain, to aapki area list adhoori hai.

---

## 8. Vadodara area list (~20 areas se shuru karo)

Alkapuri, Sayajigunj, Fatehgunj, Gotri, Manjalpur, Karelibaug, Subhanpura, Waghodia Road, Akota, Vasna, Bhayli, Sama, Harni, Makarpura, Tandalja, Nizampura, Chhani, Dandia Bazaar, Raopura, Old Padra Road, Other / Not listed

Kitne areas rakhein — trade-off:

- **Bahut kam (5-8):** posts galat area me tag honge, filtering ka matlab khatam
- **Bahut zyada (50+):** har area me 1-2 post, feed khaali lagega, aur `OTHER` bhi zyada use hoga
- **~20:** Vadodara ke size ke liye sahi. Har area me 20-30 seed posts (LAUNCH_PLAN.md Phase 2) = feed bhara hua lagega

`OTHER` ka usage percentage track karo. Agar zyada hai, list me area add karo.

---

## 9. Implementation order

Kramwar karo — har step agle ka base hai:

1. **`lib/core/location/`** — models + `gujarat_data.dart` + `LocationService`. Pure Dart, koi UI nahi. Isko test karna aasaan hai.
2. **`Post` model + repository** — `stateId`/`cityId`/`areaId`/`areaName` fields, `commentCount` fix (P0-6), `_fetchPosts` me query params.
3. **Backend** — `PostCreateRequest` fields + regex validation + `areaId.startsWith(cityId)` check, `GET /posts` me `cityId`/`areaId`/`category` params.
4. **Indexes deploy** — 4 naye composite indexes. **Console me "Enabled" ka wait karo.**
5. **Feed UI** — location chip + area sheet + city picker screen. `_showAreaPicker()` ka khaali dhaancha replace ho jaayega.
6. **Post screens** — shared `LocationSelectorField`, saaton screens me free-text hatao.
7. **Category screens** — `rooms_screen.dart:42`, `food_screen.dart:42` etc. ke client-side filters ko server query pe le jaao (step 3 ka `category` param use karke).
8. **Backfill ya wipe** — jo bhi karna ho.

**Step 3 ke baad 4 karna zaroori hai.** Query params add kar diye aur indexes nahi banaye, to production me feed khaali aa jaayegi aur error sirf backend logs me dikhega.

### Definition of done

- Vadodara select → sirf `cityId == 'GJ-VAD'` ke posts
- Alkapuri select → sirf `areaId == 'GJ-VAD-ALKAPURI'`
- "All of Vadodara" → poori city
- Surat tap → "Coming soon" + waitlist, feed nahi badalta
- Surat waitlist join karne ke baad bhi selected city Vadodara hi rahe
- App band karo, kholo → wahi city + area yaad rahe
- City badlo → area apne aap "All" pe reset ho
- Naya post banao → sirf usi city/area filter me dikhe
- Rooms/Food/Jobs tabs me posts aayein chahe woh latest 20 me na hon (P0-8 fix verify)
- Firebase console me zero "index required" errors

---

## 10. Do lines me

`area` string ko `stateId`/`cityId`/`areaId` se replace karo, `LocationService` me selected city rakho (SharedPreferences me persist), backend query me `cityId`/`areaId`/`category` params + 4 composite indexes, aur UI me location chip + area sheet + city picker banao. Har city pe `enabled` flag — sirf Vadodara `true`, baaki "Coming soon" + waitlist.

Aaj `area` likha jaata hai lekin `Post` model me map hi nahi hota, isliye **schema todne ka risk zero hai**. Poore Gujarat ka rasta ek boolean flip hai — aur Maharashtra ka rasta `kStates` list me ek entry.
