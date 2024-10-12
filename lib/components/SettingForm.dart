import 'package:flutter/material.dart';

class SettingForm extends StatefulWidget {
  @override
  _SettingFormState createState() => _SettingFormState();
}

class _SettingFormState extends State<SettingForm> {
  bool notificationsEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SwitchListTile(
          title: const Text('Enable Notifications'),
          value: notificationsEnabled,
          onChanged: (bool value) {
            setState(() {
              notificationsEnabled = value;
            });
          },
        ),
        // Add more settings here
      ],
    );
  }
}
