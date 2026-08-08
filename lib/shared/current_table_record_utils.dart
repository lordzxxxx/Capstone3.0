class CurrentTableRecordUtils {
  const CurrentTableRecordUtils._();

  static List<Map<String, dynamic>> collapseToLatestPerEntity(
    List<Map<String, dynamic>> records, {
    required List<String> idKeys,
    required List<String> nameKeys,
    List<String> dateKeys = const <String>[],
    List<String> extraIdentityKeys = const <String>[],
    String historyCountField = 'tableHistoryCount',
  }) {
    final sorted = records
        .map((record) => Map<String, dynamic>.from(record))
        .toList()
      ..sort((left, right) {
        final dateComparison = _compareDatesDescending(
          _resolveRecordDate(right, dateKeys),
          _resolveRecordDate(left, dateKeys),
        );
        if (dateComparison != 0) {
          return dateComparison;
        }
        return _compareFallbackDescending(right, left);
      });

    final deduped = <String, Map<String, dynamic>>{};
    final counts = <String, int>{};

    for (final record in sorted) {
      final key = _buildEntityKey(
        record,
        idKeys: idKeys,
        nameKeys: nameKeys,
        extraIdentityKeys: extraIdentityKeys,
      );
      counts[key] = (counts[key] ?? 0) + 1;
      deduped.putIfAbsent(key, () => record);
    }

    return deduped.entries.map((entry) {
      final record = Map<String, dynamic>.from(entry.value);
      record[historyCountField] = counts[entry.key] ?? 1;
      return record;
    }).toList();
  }

  static String buildEntityKey(
    Map<String, dynamic> record, {
    required List<String> idKeys,
    required List<String> nameKeys,
    List<String> extraIdentityKeys = const <String>[],
  }) {
    return _buildEntityKey(
      record,
      idKeys: idKeys,
      nameKeys: nameKeys,
      extraIdentityKeys: extraIdentityKeys,
    );
  }

  static DateTime? resolveRecordDate(
    Map<String, dynamic> record,
    List<String> dateKeys,
  ) {
    return _resolveRecordDate(record, dateKeys);
  }

  static String _buildEntityKey(
    Map<String, dynamic> record, {
    required List<String> idKeys,
    required List<String> nameKeys,
    required List<String> extraIdentityKeys,
  }) {
    final idValue = _firstNonEmpty(record, idKeys);
    final nameValue = _joinedNonEmpty(record, nameKeys);
    final extraValue = _joinedNonEmpty(record, extraIdentityKeys);

    if (idValue.isNotEmpty) {
      // Stable patient IDs should always map to one table entity,
      // even when demographic fields (address/contact/etc.) change.
      return 'id:$idValue';
    }
    if (nameValue.isNotEmpty) {
      return extraValue.isEmpty
          ? 'name:$nameValue'
          : 'name:$nameValue|extra:$extraValue';
    }

    final fallbackId = _safeValue(record['id']);
    if (fallbackId.isNotEmpty) {
      return 'record:$fallbackId';
    }

    return 'record:${record.hashCode}';
  }

  static String _firstNonEmpty(
    Map<String, dynamic> record,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = _safeValue(record[key]);
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  static String _joinedNonEmpty(
    Map<String, dynamic> record,
    List<String> keys,
  ) {
    final values = keys
        .map((key) => _safeValue(record[key]))
        .where((value) => value.isNotEmpty)
        .toList();
    return values.join('|');
  }

  static String _safeValue(dynamic value) {
    final text = (value ?? '').toString().trim().toLowerCase();
    return text;
  }

  static DateTime? _resolveRecordDate(
    Map<String, dynamic> record,
    List<String> dateKeys,
  ) {
    for (final key in dateKeys) {
      final parsed = _parseFlexibleDate(record[key]);
      if (parsed != null) {
        return parsed;
      }
    }
    return _parseFlexibleDate(record['updatedAt']) ??
        _parseFlexibleDate(record['createdAt']) ??
        _parseFlexibleDate(record['timestamp']);
  }

  static int _compareDatesDescending(DateTime? left, DateTime? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return -1;
    }
    if (right == null) {
      return 1;
    }
    return left.compareTo(right);
  }

  static int _compareFallbackDescending(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final leftId = _safeValue(left['id']);
    final rightId = _safeValue(right['id']);
    final leftInt = int.tryParse(leftId.replaceAll(RegExp(r'[^0-9]'), ''));
    final rightInt = int.tryParse(rightId.replaceAll(RegExp(r'[^0-9]'), ''));

    if (leftInt != null && rightInt != null && leftInt != rightInt) {
      return leftInt.compareTo(rightInt);
    }

    return leftId.compareTo(rightId);
  }

  static DateTime? _parseFlexibleDate(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is num) {
      final raw = value.toInt();
      if (raw <= 0) {
        return null;
      }
      final milliseconds = raw > 100000000000 ? raw : raw * 1000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }

    final text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }

    final direct = DateTime.tryParse(text);
    if (direct != null) {
      return direct;
    }

    final normalized = text.contains('T') ? text.split('T').first : text;
    final slashParts = normalized.split('/');
    if (slashParts.length == 3) {
      return _dateFromParts(slashParts);
    }

    final dashParts = normalized.split('-');
    if (dashParts.length == 3) {
      return _dateFromParts(dashParts);
    }

    try {
      final converted = (value as dynamic).toDate();
      if (converted is DateTime) {
        return converted;
      }
    } catch (_) {}

    return null;
  }

  static DateTime? _dateFromParts(List<String> parts) {
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    final third = int.tryParse(parts[2]);
    if (first == null || second == null || third == null) {
      return null;
    }

    if (parts[0].length == 4) {
      return DateTime(first, second, third);
    }

    return DateTime(third, first, second);
  }
}
