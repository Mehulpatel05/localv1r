import 'package:flutter/foundation.dart';
import '../models/token_claims.dart';
import 'user_action_state_service.dart';

/// ⚡ Phase 1: Client-Side Decision Matrix (UI Authorization ONLY)
/// 
/// ⚠️ IMPORTANT SECURITY BOUNDARY NOTE:
/// - This class is used EXCLUSIVELY for fast client UI rendering (showing/hiding buttons, 0ms tab switching).
/// - It is NEVER trusted for security authorization.
/// - The FastAPI backend (`SecurityDecisionEngine` in `backend/utils/security_guards.py`) is the final gatekeeper
///   that cryptographically validates token signatures and D1 database ownership on every request.
class TokenDecisionEngine {
  final TokenClaims claims;

  static TokenDecisionEngine instance = TokenDecisionEngine.anonymous();

  static void updateFromClaims(TokenClaims claims) {
    instance = TokenDecisionEngine.fromClaims(claims);
  }

  static void clear() {
    instance = TokenDecisionEngine.anonymous();
  }

  const TokenDecisionEngine({required this.claims});

  factory TokenDecisionEngine.fromClaims(TokenClaims claims) => TokenDecisionEngine(claims: claims);

  factory TokenDecisionEngine.anonymous() => TokenDecisionEngine(claims: TokenClaims.anonymous());

  // 🛡️ Core Permissions (Evaluated 100% locally from signed JWT claims)
  bool get isAuthenticated => claims.uid.isNotEmpty && claims.role != 'guest' && !claims.isExpired;
  bool get isBanned => claims.banned;
  bool get isVerified => claims.verified;
  bool get isAdmin => claims.role == 'admin';
  bool get isModerator => claims.role == 'moderator';
  bool get isShopOwner => claims.role == 'shop_owner' || claims.role == 'admin';
  bool get isProUser => claims.planTier == 'pro' || claims.role == 'admin';

  // 📝 Content Creation Rules (0ms UI Visibility)
  bool get canPost => !claims.banned;
  bool canPostListing() => !claims.banned && claims.verified;
  bool canPostJob() => !claims.banned && claims.verified;
  bool canPostRoom() => !claims.banned && claims.verified;
  bool canPostService() => !claims.banned && claims.verified;
  bool canPostFood() => !claims.banned && claims.verified;
  bool canPostEvent() => !claims.banned && claims.verified;
  bool canPostShop() => !claims.banned && (claims.role == 'shop_owner' || claims.role == 'admin');

  // 🛡️ Moderation & Administrative Privileges
  bool canSeeAdminPanel() => claims.role == 'admin' || claims.role == 'moderator';
  bool canModerateContent() => claims.role == 'admin' || claims.role == 'moderator';
  bool canBanUsers() => claims.role == 'admin';

  // 🚀 Pro Monetization & Analytics
  bool canBoostListing() => claims.planTier == 'pro' || claims.role == 'admin';
  bool canAccessAnalytics() => claims.planTier == 'pro' || claims.role == 'admin' || claims.role == 'shop_owner';

  // 💬 Social & Community Interactions
  bool canComment() => !claims.banned;
  bool canVote() => !claims.banned;
  bool canLike() => !claims.banned;

  // 📞 Calling & Direct Interaction: 2-Step Hybrid Decision
  //
  // Step 1: JWT Decision -> Is current user banned? (Instant 0ms, pure JWT, zero-DB)
  // Step 2: Block Decision -> Checked via local cache / backend query (NOT inside JWT claims)
  bool canCallUserSync(String targetHandle) {
    // 1. JWT Claim Check
    if (claims.banned) return false;

    // 2. Local Cached Block Check (Dynamic block lists are never bloated into JWT)
    final isBlocked = UserActionStateService.instance.isBlocked(targetHandle);
    return !isBlocked;
  }

  /// Asynchronous calling permission check with fallback cache hydration
  Future<bool> canCallUser(String targetHandle, {Future<bool> Function(String)? remoteBlockCheck}) async {
    // 1. JWT Check (0ms, no network)
    if (claims.banned) return false;

    // 2. Check local block state cache
    if (UserActionStateService.instance.isBlocked(targetHandle)) {
      return false;
    }

    // 3. Optional remote fetch & cache if caller provides remote checker
    if (remoteBlockCheck != null) {
      try {
        final isRemotelyBlocked = await remoteBlockCheck(targetHandle);
        if (isRemotelyBlocked) {
          UserActionStateService.instance.setActionState(
            targetId: targetHandle,
            targetType: 'user',
            isBlocked: true,
          );
          return false;
        }
      } catch (e) {
        debugPrint('[TokenDecisionEngine] Remote block check warning: $e');
      }
    }

    return true;
  }

  // ✏️ Content Ownership & Edit Permission (UI Level)
  bool canEditListing(String authorHandle) {
    if (claims.banned) return false;
    if (isAdmin || isModerator) return true;
    final myCleanHandle = claims.handle.replaceAll('@', '').trim().toLowerCase();
    final targetCleanHandle = authorHandle.replaceAll('@', '').trim().toLowerCase();
    return myCleanHandle.isNotEmpty && myCleanHandle == targetCleanHandle;
  }
}
