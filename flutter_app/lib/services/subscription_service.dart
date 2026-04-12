/// SubscriptionService
/// Tracks free trial usage and Pro subscription state.
///
/// Trial: 5 free room analyses.
/// Pro plans: Monthly ($9.99) and Annual ($59.99).
///
/// IAP product IDs must be registered in App Store Connect:
///   com.srifinance.paintmatch.pro_monthly
///   com.srifinance.paintmatch.pro_annual
///
/// The purchase flow is wired as a stub here — call [purchasePro] and
/// listen to [statusStream] from your UI. Real receipts validate via
/// in_app_purchase's [purchaseStream].
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _kOnboardingDone   = 'onboarding_complete';
const _kAnalysesUsed     = 'analyses_used';
const _kIsPro            = 'is_pro';
const _kProPlan          = 'pro_plan';        // 'monthly' | 'annual'
const _kProExpiry        = 'pro_expiry_ms';   // epoch ms

const kTrialLimit        = 5;                 // free analyses before paywall
const kProductMonthly    = 'com.srifinance.paintmatch.pro_monthly';
const kProductAnnual     = 'com.srifinance.paintmatch.pro_annual';

// ─── SubscriptionService ──────────────────────────────────────────────────────

class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._();
  factory SubscriptionService() => _instance;
  SubscriptionService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  final _statusController = StreamController<String>.broadcast();

  /// Broadcast stream for purchase status messages shown in the UI.
  Stream<String> get statusStream => _statusController.stream;

  // ── Onboarding ─────────────────────────────────────────────────────────────

  Future<bool> hasCompletedOnboarding() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kOnboardingDone) ?? false;
  }

  Future<void> markOnboardingComplete() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOnboardingDone, true);
  }

  // ── Trial ──────────────────────────────────────────────────────────────────

  Future<int> analysesUsed() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kAnalysesUsed) ?? 0;
  }

  Future<int> analysesRemaining() async {
    if (await isProActive()) return 999;
    final used = await analysesUsed();
    return (kTrialLimit - used).clamp(0, kTrialLimit);
  }

  Future<bool> canRunAnalysis() async => (await analysesRemaining()) > 0;

  Future<void> recordAnalysis() async {
    if (await isProActive()) return;
    final p = await SharedPreferences.getInstance();
    final used = p.getInt(_kAnalysesUsed) ?? 0;
    await p.setInt(_kAnalysesUsed, used + 1);
  }

  // ── Pro status ─────────────────────────────────────────────────────────────

  Future<bool> isProActive() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool(_kIsPro) ?? false)) return false;
    final expiryMs = p.getInt(_kProExpiry) ?? 0;
    if (expiryMs == 0) return true; // no expiry stored = lifetime/server-validated
    return DateTime.now().millisecondsSinceEpoch < expiryMs;
  }

  Future<String?> proPlan() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kProPlan);
  }

  /// Called after successful receipt validation (from your server or StoreKit).
  Future<void> grantPro({required String plan, DateTime? expiry}) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kIsPro, true);
    await p.setString(_kProPlan, plan);
    if (expiry != null) {
      await p.setInt(_kProExpiry, expiry.millisecondsSinceEpoch);
    }
  }

  Future<void> revokePro() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kIsPro, false);
    await p.remove(_kProPlan);
    await p.remove(_kProExpiry);
  }

  // ── In-App Purchase ────────────────────────────────────────────────────────

  /// Call once from main() or app init to listen for purchase updates.
  void listenToPurchaseUpdates() {
    _purchaseSub?.cancel();
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (e) => _statusController.add('Purchase error: $e'),
    );
  }

  Future<bool> purchasePro(String productId) async {
    final available = await _iap.isAvailable();
    if (!available) {
      _statusController.add('Store not available');
      return false;
    }

    final response = await _iap.queryProductDetails({productId});
    if (response.productDetails.isEmpty) {
      _statusController.add('Product not found — check App Store Connect');
      return false;
    }

    final purchaseParam = PurchaseParam(
      productDetails: response.productDetails.first,
    );
    return _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
    _statusController.add('Checking previous purchases…');
  }

  void _onPurchaseUpdated(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _handleSuccessfulPurchase(p);
        case PurchaseStatus.error:
          _statusController.add('Purchase failed: ${p.error?.message}');
        case PurchaseStatus.pending:
          _statusController.add('Payment pending…');
        case PurchaseStatus.canceled:
          _statusController.add('Purchase cancelled');
      }
      if (p.pendingCompletePurchase) {
        _iap.completePurchase(p);
      }
    }
  }

  void _handleSuccessfulPurchase(PurchaseDetails p) {
    // TODO: validate receipt server-side before granting access in production.
    final plan = p.productID == kProductAnnual ? 'annual' : 'monthly';
    final expiry = plan == 'annual'
        ? DateTime.now().add(const Duration(days: 365))
        : DateTime.now().add(const Duration(days: 31));
    grantPro(plan: plan, expiry: expiry);
    _statusController.add('Pro activated! Enjoy unlimited analyses.');
    debugPrint('[IAP] Purchase complete: ${p.productID}');
  }

  void dispose() {
    _purchaseSub?.cancel();
    _statusController.close();
  }
}
