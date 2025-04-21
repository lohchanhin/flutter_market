// views/MainNavigationPage.dart
// 2025‑04 ‑ 使用說明更新：Stock List 操作與原理細節

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

  final List<Widget> _widgetOptions = [
    SearchPage(),
    StockListPage(),
    NotificationSettingsPage(),
  ];

  void _onItemSelected(int index) {
    setState(() => _selectedIndex = index);
    Navigator.pop(context);
  }

  /// 使用說明對話框（加強 Stock List 部分）
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('使用說明'),
        content: const SingleChildScrollView(
          child: ListBody(
            children: [
              Text('📌 功能總覽', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('・Search：搜尋股票代碼、名稱。'),
              Text('・Stock List：瀏覽並篩選自選股。'),
              Text('・Settings：設定通知與更新方式。'),
              SizedBox(height: 12),

              // Stock List
              Text('📈 Stock List',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('1. AppBar：'),
              Text('   ‧ 🔄 同步全部'),
              Text('   ‧ 🜜 篩選條件'),
              Text('2. 篩選項目：'),
              Text('   ‧ 週期：All / 日 / 週'),
              Text('   ‧ 信號：All / TD(閃電) / TS(鑽石)'),
              Text('   ‧ PAI：開關 + 買入 / 賣出'),
              Text('   ‧ 最近 TD/TS 天數'),

              SizedBox(height: 12),
              Text('🔍 原理', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• 預設資料來源：本地 SQLite watchlist。'),
              Text('• 選擇日期後：向伺服器抓取該日信號，再依上列篩選。'),
              Text('• PAI 篩選：'),
              Text('   1) 先比對 PAI_Buy / PAI_Sell。'),
              Text('   2) 若 Switch 為開，會再計算「最後一次 TD/TS 與今天的天數 ≤ N」。'),
              Text('• 天數及 Switch 皆可即時調整，列表自動刷新。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('關閉'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('內測版本'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '使用說明',
            onPressed: _showHelpDialog,
          ),
          if (user == null)
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              },
              child: const Text('登入', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),

      // Drawer
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(user?.displayName ?? '用戶'),
              accountEmail: Text(user?.email ?? ''),
              currentAccountPicture: CircleAvatar(
                child: Text(
                  (user?.email != null && user!.email!.isNotEmpty)
                      ? user.email![0].toUpperCase()
                      : 'U',
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              decoration: const BoxDecoration(color: Colors.deepPurple),
            ),
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
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),

      body: Center(child: _widgetOptions.elementAt(_selectedIndex)),
    );
  }
}
