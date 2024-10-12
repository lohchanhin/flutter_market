import 'package:flutter/material.dart';
import '../components/SettingForm.dart'; // 確保導入正確

class NotificationSettingsPage extends StatelessWidget {
  NotificationSettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notification Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SettingForm(),
      ),
    );
  }
}
