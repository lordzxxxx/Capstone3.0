import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:mycapstone_project/firebase_helper.dart';

// Mirrors lib/main.dart's kUseFirebaseEmulator flag. Declared separately
// (rather than imported) to avoid a dependency on the app entrypoint; both
// read the same --dart-define, so they always agree at compile time.
const bool _kUseFirebaseEmulator = bool.fromEnvironment(
  'USE_FIREBASE_EMULATOR',
);
const bool _kBrowserQaMode = bool.fromEnvironment('BROWSER_QA');

Uri _firestoreRestUri(String path, Map<String, String> queryParameters) {
  if (_kUseFirebaseEmulator && (!kReleaseMode || _kBrowserQaMode)) {
    return Uri.http('localhost:8085', path, queryParameters);
  }
  return Uri.https('firestore.googleapis.com', path, queryParameters);
}

class FirestoreRestDocument {
  const FirestoreRestDocument({required this.id, required this.fields});

  final String id;
  final Map<String, dynamic> fields;

  Map<String, dynamic> data() => fields;
}

class FirestoreRestReader {
  const FirestoreRestReader();

  Future<FirestoreRestDocument?> getDocument(
    String collectionId,
    String documentId,
  ) async {
    final request = await _requestContext();
    final uri = _firestoreRestUri(
      '/v1/projects/${request.projectId}/databases/$kFirestoreDatabaseId/documents/$collectionId/$documentId',
      {'key': request.apiKey},
    );
    final response = await http
        .get(uri, headers: request.headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_responseError(response));
    }
    final document = jsonDecode(response.body) as Map<String, dynamic>;
    final name = (document['name'] ?? '').toString();
    final rawFields = document['fields'];
    return FirestoreRestDocument(
      id: name.isEmpty ? documentId : name.split('/').last,
      fields: rawFields is Map
          ? _decodeFields(Map<String, dynamic>.from(rawFields))
          : <String, dynamic>{},
    );
  }

  Future<List<FirestoreRestDocument>> listCollection(
    String collectionId, {
    int pageSize = 300,
    String parentDocumentPath = '',
    Map<String, Object?> equalTo = const <String, Object?>{},
  }) async {
    final request = await _requestContext();
    final results = <FirestoreRestDocument>[];
    final uri = _firestoreRestUri(
      '/v1/projects/${request.projectId}/databases/$kFirestoreDatabaseId/documents${parentDocumentPath.trim().isEmpty ? '' : '/${parentDocumentPath.trim()}'}:runQuery',
      {'key': request.apiKey},
    );
    final filters = equalTo.entries
        .map(
          (entry) => <String, dynamic>{
            'fieldFilter': {
              'field': {'fieldPath': entry.key},
              'op': 'EQUAL',
              'value': _encodeValue(entry.value),
            },
          },
        )
        .toList(growable: false);
    final response = await http
        .post(
          uri,
          headers: {...request.headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'structuredQuery': {
              'from': [
                {'collectionId': collectionId},
              ],
              if (filters.length == 1) 'where': filters.first,
              if (filters.length > 1)
                'where': {
                  'compositeFilter': {'op': 'AND', 'filters': filters},
                },
              'limit': pageSize.clamp(1, 1000),
            },
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_responseError(response));
    }
    final payload = jsonDecode(response.body);
    if (payload is List) {
      for (final row in payload.whereType<Map>()) {
        final rawDocument = row['document'];
        if (rawDocument is! Map) continue;
        final document = Map<String, dynamic>.from(rawDocument);
        final name = (document['name'] ?? '').toString();
        final rawFields = document['fields'];
        results.add(
          FirestoreRestDocument(
            id: name.split('/').last,
            fields: rawFields is Map
                ? _decodeFields(Map<String, dynamic>.from(rawFields))
                : <String, dynamic>{},
          ),
        );
      }
    }
    return results;
  }

  Future<_FirestoreRestRequestContext> _requestContext() async {
    final user = FirebaseAuth.instance.currentUser;
    // Reuse the current valid token. Several dashboard collections are loaded
    // concurrently; forcing a refresh for every request can create competing
    // token-refresh operations in Flutter Web.
    final idToken = await user?.getIdToken();
    if (user == null || idToken == null || idToken.isEmpty) {
      throw StateError(
        'Your Firebase session has expired. Please sign in again.',
      );
    }
    final app = Firebase.app();
    final projectId = app.options.projectId;
    final apiKey = app.options.apiKey;
    if (projectId.isEmpty || apiKey.isEmpty) {
      throw StateError('Firebase project configuration is incomplete.');
    }
    String? appCheckToken;
    try {
      appCheckToken = await FirebaseAppCheck.instance.getToken();
    } catch (_) {}
    return _FirestoreRestRequestContext(
      projectId: projectId,
      apiKey: apiKey,
      headers: {
        'Authorization': 'Bearer $idToken',
        if (appCheckToken != null && appCheckToken.isNotEmpty)
          'X-Firebase-AppCheck': appCheckToken,
      },
    );
  }

  Map<String, dynamic> _decodeFields(Map<String, dynamic> fields) => fields.map(
    (key, value) => MapEntry(
      key,
      value is Map ? _decodeValue(Map<String, dynamic>.from(value)) : value,
    ),
  );

  dynamic _decodeValue(Map<String, dynamic> value) {
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('booleanValue')) return value['booleanValue'];
    if (value.containsKey('integerValue')) {
      return int.tryParse(value['integerValue'].toString()) ?? 0;
    }
    if (value.containsKey('doubleValue')) return value['doubleValue'];
    if (value.containsKey('timestampValue')) return value['timestampValue'];
    if (value.containsKey('referenceValue')) return value['referenceValue'];
    if (value.containsKey('geoPointValue')) return value['geoPointValue'];
    final mapValue = value['mapValue'];
    if (mapValue is Map && mapValue['fields'] is Map) {
      return _decodeFields(
        Map<String, dynamic>.from(mapValue['fields'] as Map),
      );
    }
    final arrayValue = value['arrayValue'];
    if (arrayValue is Map && arrayValue['values'] is List) {
      return (arrayValue['values'] as List)
          .whereType<Map>()
          .map((item) => _decodeValue(Map<String, dynamic>.from(item)))
          .toList();
    }
    return null;
  }

  Map<String, dynamic> _encodeValue(Object? value) {
    if (value == null) return const {'nullValue': null};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': value.toString()};
    if (value is double) return {'doubleValue': value};
    return {'stringValue': value.toString()};
  }

  String _responseError(http.Response response) {
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final error = payload['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
    } catch (_) {}
    return 'Firestore REST request failed (${response.statusCode}).';
  }
}

class _FirestoreRestRequestContext {
  const _FirestoreRestRequestContext({
    required this.projectId,
    required this.apiKey,
    required this.headers,
  });

  final String projectId;
  final String apiKey;
  final Map<String, String> headers;
}
