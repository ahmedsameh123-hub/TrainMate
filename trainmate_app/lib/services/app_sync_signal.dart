import 'package:flutter/foundation.dart';

/// Global lightweight refresh signal for post-login/session hydration updates.
class AppSyncSignal {
  static final ValueNotifier<int> refreshTick = ValueNotifier<int>(0);

  static void notifyRefresh() {
    refreshTick.value = refreshTick.value + 1;
  }
}
