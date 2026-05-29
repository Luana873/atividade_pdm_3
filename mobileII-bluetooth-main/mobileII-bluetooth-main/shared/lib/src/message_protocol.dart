import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'message_batch_item.dart';
import 'message_packet.dart';

class MessageProtocol {
  const MessageProtocol._();

  static String newMessageId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
  }

  static Uint8List encodeMessage(String id, String text) {
    return Uint8List.fromList(
      utf8.encode(jsonEncode({'type': 'message', 'id': id, 'text': text})),
    );
  }

  static Uint8List encodeBatch(List<MessageBatchItem> messages) {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'type': 'batch',
          'messages': messages
              .map((message) => {'id': message.id, 'text': message.text})
              .toList(),
        }),
      ),
    );
  }

  static Uint8List encodeOpened(String messageId) {
    return Uint8List.fromList(
      utf8.encode(jsonEncode({'type': 'opened', 'id': messageId})),
    );
  }

  static MessagePacket decodePacket(String text) {
    try {
      final json = jsonDecode(text);
      if (json is Map<String, dynamic>) {
        final type = json['type'];
        final id = json['id'];
        if (type == 'opened' && id is String) {
          return MessagePacket.opened(id);
        }
        final message = json['text'];
        if (type == 'message' && id is String && message is String) {
          return MessagePacket.message(id: id, text: message);
        }
      }
    } catch (_) {
      // Mensagens antigas eram texto puro.
    }

    return MessagePacket.message(id: newMessageId(), text: text);
  }

  static List<MessagePacket> decodePackets(String text) {
    try {
      final json = jsonDecode(text);
      if (json is Map<String, dynamic> && json['type'] == 'batch') {
        final messages = json['messages'];
        if (messages is List) {
          return messages
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((item) => item['id'] is String && item['text'] is String)
              .map(
                (item) => MessagePacket.message(
                  id: item['id'] as String,
                  text: item['text'] as String,
                ),
              )
              .toList();
        }
      }
    } catch (_) {
      // O pacote simples sera tratado abaixo.
    }

    return [decodePacket(text)];
  }
}
