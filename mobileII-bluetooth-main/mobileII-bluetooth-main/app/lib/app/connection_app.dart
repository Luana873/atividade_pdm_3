import 'package:flutter/material.dart';

import '../features/connection/connection_screen.dart';

class ConnectionApp extends StatelessWidget {
  const ConnectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Conexão',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const ConnectionScreen(),
    );
  }
}
