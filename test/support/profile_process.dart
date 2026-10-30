import 'dart:convert';
import 'dart:io';
import '../../lib/storage/profile_lease.dart';

Future<void> main(List<String> args) async {
  final directory = Directory(args.first);
  Future<void> attempt() async {
    try {
      await ProfileLease.acquire(directory);
      // Represents DB/Vault access. A rejected second owner must never touch it.
      await File(
        '${directory.path}/writes',
      ).writeAsString('$pid\n', mode: FileMode.append);
      stdout.writeln('acquired');
    } on Object {
      stdout.writeln('busy');
    }
  }

  await attempt();
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line == 'exit') break;
    if (line == 'retry') await attempt();
  }
}
