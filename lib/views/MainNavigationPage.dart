// views/MainNavigationPage.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'SearchPage.dart';
import 'StockListPage.dart';
import 'NotificationSettingsPage.dart';
import 'login.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({Key? key}) : super(key: key);

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;
  final List<Widget> _widgetOptions = <Widget>[
    SearchPage(),
    StockListPage(),
    NotificationSettingsPage(),
  ];

  void _onItemSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // 選擇完選單項目後關閉 Drawer
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // 取得當前用戶資訊（若為 null 則視為未登入）
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('內測版本'),
        // 若用戶未登入，可在 AppBar 顯示「登入」按鈕
        actions: [
          if (user == null)
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                );
              },
              child: const Text(
                "登入",
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      // Drawer 取代原本的底部導覽列
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            // 利用 UserAccountsDrawerHeader 顯示用戶資訊
            UserAccountsDrawerHeader(
              accountName: Text(user?.displayName ?? "用戶"),
              accountEmail: Text(user?.email ?? ""),
              currentAccountPicture: CircleAvatar(
                child: Text(
                  (user?.email != null && user!.email!.isNotEmpty)
                      ? user.email![0].toUpperCase()
                      : 'U',
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              decoration: const BoxDecoration(
                color: Colors.deepPurple,
              ),
            ),
            // Drawer 選單項目
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search'),
              selected: _selectedIndex == 0,
              onTap: () => _onItemSelected(0),
            ),
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text('Stock List'),
              selected: _selectedIndex == 1,
              onTap: () => _onItemSelected(1),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              selected: _selectedIndex == 2,
              onTap: () => _onItemSelected(2),
            ),
            const Divider(),
            // 額外提供登出功能
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                // 登出後關閉 Drawer
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
    );
  }
}
