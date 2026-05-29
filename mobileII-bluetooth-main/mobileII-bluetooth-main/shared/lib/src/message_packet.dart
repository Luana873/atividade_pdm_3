enum MessagePacketType { message, opened }

class MessagePacket {
  const MessagePacket._({
    required this.type,
    required this.id,
    required this.text,
  });

  factory MessagePacket.message({required String id, required String text}) {
    return MessagePacket._(type: MessagePacketType.message, id: id, text: text);
  }

  factory MessagePacket.opened(String id) {
    return MessagePacket._(type: MessagePacketType.opened, id: id, text: '');
  }

  final MessagePacketType type;
  final String id;
  final String text;
}
