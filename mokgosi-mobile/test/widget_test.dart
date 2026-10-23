import 'package:flutter_test/flutter_test.dart';
import 'package:mokgosi_mobile/main.dart';

void main() {
  testWidgets('escort home renders the start action', (tester) async {
    await tester.pumpWidget(const MokgosiApp());
    expect(find.text('MOKGOSI'), findsOneWidget);
    expect(find.text('START 30 SECOND ESCORT'), findsOneWidget);
  });
}
