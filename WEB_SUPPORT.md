# Web Platform Support

This application now supports running on web browsers in addition to mobile platforms (Android/iOS).

## Architecture

### Mobile Platform (Android/iOS)
- **Local Storage**: SQLite database for offline-first operation
- **Cloud Sync**: Automatic synchronization with Firebase Firestore when internet is available
- **Connectivity Detection**: Uses connectivity_plus to monitor network status

### Web Platform
- **Storage**: Direct Firebase Firestore integration (no SQLite)
- **Real-time**: All CRUD operations happen directly on Firebase
- **No Offline Mode**: Web version requires internet connection

## Platform Detection

The application uses `kIsWeb` from `package:flutter/foundation.dart` to detect the platform at runtime:

```dart
if (kIsWeb) {
  // Use Firebase directly
} else {
  // Use SQLite + Firebase sync
}
```

## Database Helpers

All three database helpers support both platforms:
- `database_helper.dart` - CheckUp records
- `prenatal_database_helper.dart` - Prenatal records
- `immunization_database_helper.dart` - Immunization records

### Methods Supporting Both Platforms:
- `insertRecord()` - Save new records
- `getAllRecords()` - Fetch all records
- `updateRecord()` - Update existing records
- `deleteRecord()` - Delete single record
- `deleteRecords()` - Delete multiple records

## Building for Web

### Development
```bash
flutter run -d chrome
```

### Production Build
```bash
flutter build web
```

### Deploy
The built web files will be in the `build/web` directory. Deploy to:
- Firebase Hosting
- GitHub Pages
- Any static web hosting service

## Firebase Configuration

The web/index.html file includes Firebase SDK scripts:
```html
<script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-firestore-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-auth-compat.js"></script>
```

Make sure your Firebase project is properly configured in `lib/main.dart`.

## Dependencies

The following packages support web:
- `cloud_firestore` - Firebase Firestore
- `firebase_core` - Firebase Core
- `firebase_auth` - Firebase Authentication
- `community_charts_flutter` - Charts (web compatible)
- `get` - Navigation and state management

## Limitations on Web

1. **No Offline Mode**: Web version cannot work offline
2. **No SQLite**: SQLite is not available on web
3. **Connectivity Monitoring**: connectivity_plus has limited functionality on web

## Testing

To test the web version locally:
```bash
flutter run -d chrome --web-hostname localhost --web-port 8080
```

## Analytics

The Analytics dashboard works identically on both platforms:
- Real-time data updates every 10 seconds
- Fetches data from Firebase Firestore
- Displays charts and statistics

## Best Practices

1. **Error Handling**: All database operations include try-catch blocks
2. **Platform Checks**: Always check `kIsWeb` before platform-specific code
3. **Null Safety**: All fields have default values ('')
4. **Consistent API**: Same method signatures across platforms

## Future Enhancements

- Add IndexedDB support for web offline storage
- Implement service workers for offline capability
- Add PWA (Progressive Web App) support
- Optimize bundle size for faster web loading
