part of '../connection_screen.dart';

class _AparelhoEncontrado {
  const _AparelhoEncontrado({required this.id, required this.nome});

  final String id;
  final String nome;
}

class _Conversa {
  const _Conversa({
    required this.id,
    required this.deviceId,
    required this.nome,
    required this.subtitulo,
    required this.tipo,
    required this.icone,
  });

  final String id;
  final String deviceId;
  final String nome;
  final String subtitulo;
  final _TipoConversa tipo;
  final IconData icone;
}

class _MensagemChat {
  const _MensagemChat({
    required this.id,
    required this.conversaId,
    required this.texto,
    required this.remetente,
    required this.enviadaPorMim,
    required this.status,
  });

  final String id;
  final String conversaId;
  final String texto;
  final String remetente;
  final bool enviadaPorMim;
  final MessageStatus status;

  _MensagemChat copyWith({MessageStatus? status}) {
    return _MensagemChat(
      id: id,
      conversaId: conversaId,
      texto: texto,
      remetente: remetente,
      enviadaPorMim: enviadaPorMim,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversaId': conversaId,
      'texto': texto,
      'remetente': remetente,
      'enviadaPorMim': enviadaPorMim,
      'status': status.name,
    };
  }

  factory _MensagemChat.fromJson(Map<String, dynamic> json) {
    return _MensagemChat(
      id: json['id'] as String? ?? '',
      conversaId: json['conversaId'] as String? ?? '',
      texto: json['texto'] as String? ?? '',
      remetente: json['remetente'] as String? ?? '',
      enviadaPorMim: json['enviadaPorMim'] as bool? ?? false,
      status: MessageStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => MessageStatus.recebida,
      ),
    );
  }
}
