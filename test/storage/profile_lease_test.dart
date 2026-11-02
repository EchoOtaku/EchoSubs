import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

class Child {
  Child(this.process)
    : lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
  final Process process;
  final StreamIterator<String> lines;
  static Future<Child> start(Directory dir) async {
    final dart = Platform.environment['FLUTTER_ROOT'] == null
        ? '${File(Platform.resolvedExecutable).parent.parent.parent.parent.path}/dart-sdk/bin/dart.exe'
        : '${Platform.environment['FLUTTER_ROOT']}/bin/cache/dart-sdk/bin/dart.exe';
    final process = await Process.start(dart, [
      'test/support/profile_process.dart',
      dir.path,
    ]);
    // All children own synthetic directories and are closed in finally.
    // ignore: avoid_print
    print('OWNED lease child PID=${process.pid}');
    return Child(process);
  }

  Future<String> next() async {
    if (!await lines.moveNext().timeout(const Duration(seconds: 10))) {
      throw StateError(
        'child ended: ${await process.stderr.transform(utf8.decoder).join()}',
      );
    }
    return lines.current;
  }

  Future<void> close() async {
    process.stdin.writeln('exit');
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill();
      await process.exitCode;
    }
    await lines.cancel();
  }
}

void main() {
  test(
    'I7 independent processes exclude same profile until holder exits; retry and isolated profiles work',
    () async {
      final dir = await Directory.systemTemp.createTemp('echosubs-lease-');
      final other = await Directory.systemTemp.createTemp(
        'echosubs-lease-other-',
      );
      final a = await Child.start(dir);
      Child? b, c;
      try {
        expect(await a.next(), 'acquired');
        b = await Child.start(dir);
        expect(await b.next(), 'busy');
        expect((await File('${dir.path}/writes').readAsLines()).length, 1);
        c = await Child.start(other);
        expect(await c.next(), 'acquired');
        a.process.stdin.writeln('retry');
        expect(await a.next(), 'acquired');
        await a.close();
        b.process.stdin.writeln('retry');
        expect(await b.next(), 'acquired');
      } finally {
        if (a.process.kill()) await a.process.exitCode;
        await b?.close();
        await c?.close();
      }
    },
    skip: !Platform.isWindows,
  );
}
