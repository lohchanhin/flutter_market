import 'package:flutter/material.dart';

class SearchBar2 extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onSearch;

  const SearchBar2({Key? key, required this.controller, required this.onSearch})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: 'Search stocks',
        suffixIcon: Icon(Icons.search),
        border: OutlineInputBorder(),
      ),
      onChanged: onSearch,
    );
  }
}
