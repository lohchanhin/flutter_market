import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'views/login.dart'; // 登入介面
import 'views/MainNavigationPage.dart'; // 主頁面
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 Firebase，使用 CLI 產生的選項
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '振興自製台股app',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // 根據用戶登入狀態決定進入頁面
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  // 檢查帳號是否有效（刷新 token）
  Future<bool> checkAccountStatus(User user) async {
    try {
      await user.getIdTokenResult(true); // 強制刷新 token
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-disabled' ||
          e.code == 'user-token-expired' ||
          e.code == 'user-not-found') {
        await FirebaseAuth.instance.signOut();
        return false;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginPage();
        }

        // 當 user 存在時，再進一步檢查是否仍有效
        return FutureBuilder<bool>(
          future: checkAccountStatus(user),
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (authSnapshot.data == true) {
              return const MainNavigationPage();
            } else {
              return const LoginPage();
            }
          },
        );
      },
    );
  }
}
