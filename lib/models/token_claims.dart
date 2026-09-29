class TokenClaims {
  final String uid;
  final String role; // 'user', 'shop_owner', 'admin', 'moderator'
  final String cityId;
  final bool verified;
  final String handle;
  final String planTier; // 'free', 'pro'
  final bool banned;
  final int tokenVersion;
  final int? exp;

  const TokenClaims({
    required this.uid,
    required this.role,
    required this.cityId,
    required this.verified,
    required this.handle,
    required this.planTier,
    required this.banned,
    required this.tokenVersion,
    this.exp,
  });

  factory TokenClaims.anonymous() => const TokenClaims(
        uid: '',
        role: 'guest',
        cityId: 'surat_gujarat',
        verified: false,
        handle: 'guest',
        planTier: 'free',
        banned: false,
        tokenVersion: 1,
      );

  factory TokenClaims.fromJwtMap(Map<String, dynamic> json) {
    return TokenClaims(
      uid: json['uid']?.toString() ?? json['sub']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      cityId: json['cityId']?.toString() ?? json['city_id']?.toString() ?? 'surat_gujarat',
      verified: json['verified'] == true || json['verified'] == 1,
      handle: json['handle']?.toString() ?? '',
      planTier: json['planTier']?.toString() ?? json['plan_tier']?.toString() ?? 'free',
      banned: json['banned'] == true || json['banned'] == 1,
      tokenVersion: (json['tokenVersion'] ?? json['token_version'] ?? 1) is int
          ? (json['tokenVersion'] ?? json['token_version'] ?? 1)
          : int.tryParse((json['tokenVersion'] ?? json['token_version'] ?? 1).toString()) ?? 1,
      exp: json['exp'] is int ? json['exp'] : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'role': role,
        'cityId': cityId,
        'verified': verified,
        'handle': handle,
        'planTier': planTier,
        'banned': banned,
        'tokenVersion': tokenVersion,
        'exp': exp,
      };

  bool get isExpired {
    if (exp == null) return false;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowSeconds >= exp!;
  }
}
