import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDpMpewyKVlfsfSeKfoS3GJf0V_t14Qb7k',
    appId: 'PROVIDER_APP_ID',
    messagingSenderId: '1064274729048',
    projectId: 'hamaraservice-s009',
    databaseURL: 'https://hamaraservice-s009-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'hamaraservice-s009.firebasestorage.app',
  );
}
