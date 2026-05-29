import 'package:flutter_test/flutter_test.dart';

import 'package:exemplo_quatro/app/connection_app.dart';

void main() {
  testWidgets('mostra tela principal de conexao', (tester) async {
    await tester.pumpWidget(const ConnectionApp());

    expect(find.text('Conexão Bluetooth'), findsOneWidget);
  });
}
