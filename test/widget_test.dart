import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:splayer_keygen/src/theme.dart';

void main() {
  test('主题为深色，主色 #00E676', () {
    final theme = buildAppTheme();
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary.toARGB32(), 0xFF00E676);
  });
}
