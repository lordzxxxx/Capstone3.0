import 'package:sqflite/sqflite.dart';

/// Remote refreshes must not replace an offline edit that is still waiting for
/// outbound sync. Each database helper keeps its existing schema and sync
/// strategy; this small guard only protects the local pending row.
Future<bool> hasPendingLocalSync(
  Database db, {
  required String table,
  required String id,
}) async {
  final rows = await db.query(
    table,
    columns: const ['synced'],
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return rows.isNotEmpty && rows.first['synced'] == 0;
}
