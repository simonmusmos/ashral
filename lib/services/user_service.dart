import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  static final UserService instance = UserService._();
  UserService._();

  String get userId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('UserService.userId called before sign-in');
    return uid;
  }

  /// No-op — kept so main() doesn't need to change.
  Future<void> init() async {}
}
