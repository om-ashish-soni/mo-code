import 'package:flutter_test/flutter_test.dart';

import 'package:mo_code/main.dart';

void main() {
  testWidgets('App renders with navigation bar', (WidgetTester tester) async {
    await tester.pumpWidget(const MoCodeApp());
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
  });
}
