import 'package:flutter/foundation.dart';

class AppNavigation {
  AppNavigation({int initialTab = 0})
    : selectedTab = ValueNotifier<int>(initialTab),
      recordsVersion = ValueNotifier<int>(0);

  final ValueNotifier<int> selectedTab;
  final ValueNotifier<int> recordsVersion;

  void selectTab(int index) {
    selectedTab.value = index;
  }

  void notifyRecordsChanged() {
    recordsVersion.value++;
  }

  void reset() {
    selectedTab.value = 0;
    recordsVersion.value = 0;
  }
}

final AppNavigation appNavigation = AppNavigation();
