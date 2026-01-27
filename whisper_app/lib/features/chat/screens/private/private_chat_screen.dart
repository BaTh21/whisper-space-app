import 'package:flutter/material.dart';

class PrivateChatScreen extends StatelessWidget{
  final int userId;
  final String userName;

  const PrivateChatScreen({
    super.key,
    required this.userId,
    required this.userName
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(userName),),
      body: Center(
        child: Text('Private chat with $userName'),
      ),
    );
  }
}