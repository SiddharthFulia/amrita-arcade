import 'package:flutter_test/flutter_test.dart';
import 'package:amrita/main.dart';

void main() {
  testWidgets('arcade boots', (tester) async {
    await tester.pumpWidget(const ArcadeApp());
    expect(find.text('amrita arcade'), findsOneWidget);
  });
}
