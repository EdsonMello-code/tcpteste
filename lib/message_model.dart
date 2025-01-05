import 'dart:convert';

class Message {
  final String type;
  final Map<String, dynamic> data;

  Message({required this.type, required this.data});

  Map<String, dynamic> toJson() => {
        'type': type,
        'data': data,
      };

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      type: json['type'],
      data: json['data'],
    );
  }

  String encode() => jsonEncode(toJson());

  static Message decode(String data) {
    final json = jsonDecode(data);
    return Message.fromJson(json);
  }
}
