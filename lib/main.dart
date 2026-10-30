import 'package:flutter/material.dart';

void main() => runApp(const EchoSubsApp());

class EchoSubsApp extends StatelessWidget {
  const EchoSubsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EchoSubs 订阅簿',
    home: Scaffold(
      appBar: AppBar(title: const Text('EchoSubs 订阅簿')),
      body: const Center(child: Text('本地账本准备就绪')),
    ),
  );
}
