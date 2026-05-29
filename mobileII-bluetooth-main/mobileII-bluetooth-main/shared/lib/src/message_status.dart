enum MessageStatus { digitada, recebida, aberta }

extension MessageStatusLabel on MessageStatus {
  String get rotulo {
    return switch (this) {
      MessageStatus.digitada => 'Digitada',
      MessageStatus.recebida => 'Recebida',
      MessageStatus.aberta => 'Aberta',
    };
  }
}
