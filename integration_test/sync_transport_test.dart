import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:its_app/sync/sync_diagnostics.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('SYNC_SMOKE_URL');
  testWidgets('embedded native transport reaches gateway without credentials', (
    tester,
  ) async {
    final status = await probeSyncHttp(
      Uri.parse(endpoint),
      timeout: const Duration(seconds: 20),
    );
    // This deliberately supplies no key. A 401 verifies transport without
    // logging in or reading/writing any account data.
    expect(status, 401);
  }, skip: endpoint.isEmpty);
}
