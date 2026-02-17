import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

final _log = Logger('Bank');

class Bank {
  final int id;
  final String title;
  final List<String> pedalboardBundles;

  Bank({required this.id, required this.title, required this.pedalboardBundles});

  factory Bank.fromJson(int id, Map<String, dynamic> json) {
    final pedalboards = (json['pedalboards'] as List<dynamic>?) ?? [];
    return Bank(
      id: id,
      title: json['title'] as String? ?? 'Unnamed Bank',
      pedalboardBundles: pedalboards
          .map((pb) => pb['bundle'] as String?)
          .where((b) => b != null)
          .cast<String>()
          .toList(),
    );
  }

  /// Load all banks from the banks.json file
  /// Returns a list with "All Pedalboards" as the first entry (id=1),
  /// followed by user banks (id=2, 3, ...)
  static Future<List<Bank>> loadAll() async {
    final banks = <Bank>[];

    // Add "All Pedalboards" as the first option (bank id 1)
    banks.add(Bank(id: 1, title: 'All Pedalboards', pedalboardBundles: []));

    // Try to load user banks from JSON
    // Use MOD_DATA_DIR env var, fallback to $HOME/data
    final dataDir = Platform.environment['MOD_DATA_DIR'] ??
        '${Platform.environment['HOME']}/data';
    final banksFile = File('$dataDir/banks.json');

    if (await banksFile.exists()) {
      try {
        final content = await banksFile.readAsString();
        final List<dynamic> jsonBanks = jsonDecode(content);

        for (var i = 0; i < jsonBanks.length; i++) {
          // User banks start at id 2 (after "All Pedalboards")
          banks.add(Bank.fromJson(i + 2, jsonBanks[i]));
        }
        _log.info('Loaded ${jsonBanks.length} user banks');
      } catch (e) {
        _log.warning('Failed to load banks: $e');
      }
    } else {
      _log.info('No banks.json found at ${banksFile.path}');
    }

    return banks;
  }

  @override
  String toString() => 'Bank($id: $title)';
}
