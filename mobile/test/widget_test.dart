import 'package:flutter_test/flutter_test.dart';
import 'package:janjatisetu/core/storage.dart';
import 'package:janjatisetu/main.dart';
import 'package:janjatisetu/screens/student/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Smoke test. Also stops `flutter create .` from generating its default
// widget_test.dart, which references a `MyApp` class this project doesn't have.
void main() {
  testWidgets('signed-out users land on the login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.instance();

    await tester.pumpWidget(JanjatiSetuApp(store: store));
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
