import 'package:flutter/material.dart';

/// A minimal JSON data model with a tolerant fromJson factory.
class UserModel {
  const UserModel({required this.name});

  final String name;

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      UserModel(name: json['name'] as String? ?? '');
}

/// ChangeNotifier state used by the home screen.
class UserModelNotifier extends ChangeNotifier {
  UserModelNotifier({this.user});

  UserModel? user;

  void load(Map<String, dynamic> json) {
    user = UserModel.fromJson(json);
    notifyListeners();
  }
}
