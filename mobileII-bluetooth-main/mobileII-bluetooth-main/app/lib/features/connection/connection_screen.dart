import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:connection_shared/connection_shared.dart';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/connection_foreground_service.dart';

part 'models/connection_models.dart';
part 'data/message_protocol.dart';
part 'widgets/connection_widgets.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

enum _AcaoMenu {
  editarNome,
  buscarCelulares,
}

enum _TipoConversa {
  celular,
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with WidgetsBindingObserver {
  static const String _serviceId = 'br.sp.gov.cps.dsm.chat';
  static const String _nomeUsuarioPrefsKey = 'connection_user_name';
  static const String _mensagensPrefsKey = 'connection_messages';
  static const Strategy _strategy = Strategy.P2P_CLUSTER;

  final TextEditingController _mensagemController =
      TextEditingController();

  final List<_AparelhoEncontrado> _aparelhosEncontrados = [];
  final Map<String, ConnectionInfo> _aparelhosConectados = {};
  final List<_MensagemChat> _mensagens = [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  String? _conversaSelecionadaId;
  VoidCallback? _atualizarModalBusca;

  bool _anunciando = false;
  bool _alternandoDisponibilidade = false;
  bool _procurando = false;
  bool _conectando = false;
  bool _appEmPrimeiroPlano = true;

  String? _mensagemErro;

  late String _nomeUsuario;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _nomeUsuario =
        'Aparelho ${Random().nextInt(9000) + 1000}';

    unawaited(_inicializarDisponibilidade());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _mensagemController.dispose();

    for (final subscription in _subscriptions) {
      subscription.cancel();
    }

    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    final emPrimeiroPlano =
        state == AppLifecycleState.resumed;

    if (_appEmPrimeiroPlano == emPrimeiroPlano) {
      return;
    }

    _appEmPrimeiroPlano = emPrimeiroPlano;

    if (emPrimeiroPlano &&
        _conversaSelecionadaId != null) {
      _marcarConversaComoAberta(
        _conversaSelecionadaId!,
      );
    }
  }

  Future<void> _inicializarDisponibilidade() async {
    await _carregarNomeUsuario();
    await _carregarHistoricoMensagens();

    if (!mounted) return;

    await _garantirDisponibilidade();
  }

  Future<void> _carregarNomeUsuario() async {
    final prefs = await SharedPreferences.getInstance();

    final nomeSalvo =
        prefs.getString(_nomeUsuarioPrefsKey)?.trim();

    if (!mounted ||
        nomeSalvo == null ||
        nomeSalvo.isEmpty) {
      return;
    }

    setState(() {
      _nomeUsuario = nomeSalvo;
    });
  }

  Future<void> _carregarHistoricoMensagens() async {
    final prefs = await SharedPreferences.getInstance();

    final historico =
        prefs.getString(_mensagensPrefsKey);

    if (!mounted ||
        historico == null ||
        historico.isEmpty) {
      return;
    }

    final json = jsonDecode(historico);

    if (json is! List) return;

    setState(() {
      _mensagens
        ..clear()
        ..addAll(
          json.whereType<Map>().map(
                (item) => _MensagemChat.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              ),
        );
    });
  }

  Future<void> _persistirMensagens() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _mensagensPrefsKey,
      jsonEncode(
        _mensagens
            .map((mensagem) => mensagem.toJson())
            .toList(),
      ),
    );
  }

  Future<void> _abrirEdicaoNome() async {
    final nome = await showDialog<String>(
      context: context,
      builder: (_) =>
          _DialogEdicaoNome(nomeInicial: _nomeUsuario),
    );

    final nomeNormalizado = nome?.trim();

    if (nomeNormalizado == null ||
        nomeNormalizado.isEmpty ||
        !mounted) {
      return;
    }

    final estavaDisponivel = _anunciando;

    if (estavaDisponivel) {
      await _pararAnuncio();
    }

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _nomeUsuarioPrefsKey,
      nomeNormalizado,
    );

    if (!mounted) return;

    setState(() {
      _nomeUsuario = nomeNormalizado;
    });

    if (estavaDisponivel) {
      await _iniciarAnuncio();
    }
  }

  Future<void> _garantirDisponibilidade() async {
    if (_anunciando ||
        _alternandoDisponibilidade) {
      return;
    }

    setState(() {
      _mensagemErro = null;
      _alternandoDisponibilidade = true;
    });

    try {
      await _iniciarAnuncio();
    } catch (erro) {
      if (_erroJaEstaAnunciando(erro)) {
        if (mounted) {
          setState(() {
            _anunciando = true;
          });
        }

        return;
      }

      _definirErro(
        'Não foi possível deixar este aparelho disponível: $erro',
      );
    } finally {
      if (mounted) {
        setState(() {
          _alternandoDisponibilidade = false;
        });
      }
    }
  }

  Future<bool> _pedirPermissoes() async {
    final localizacao =
        await Permission.locationWhenInUse.request();

    if (localizacao.isDenied ||
        localizacao.isPermanentlyDenied) {
      _mostrarMensagem(
        'Permissão de localização negada.',
      );

      return false;
    }

    await <Permission>[
      Permission.notification,
      Permission.bluetoothAdvertise,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();

    final localizacaoAtiva =
        await Permission.locationWhenInUse
            .serviceStatus
            .isEnabled;

    if (!localizacaoAtiva) {
      _mostrarMensagem(
        'Ative a localização do aparelho para descobrir outros dispositivos.',
      );

      return false;
    }

    return true;
  }

  Future<void> _pararAnuncio() async {
    await Nearby().stopAdvertising();

    if (!mounted) return;

    setState(() {
      _anunciando = false;
    });
  }

  Future<void> _iniciarAnuncio() async {
    if (!await _pedirPermissoes()) {
      return;
    }

    await ConnectionForegroundService.start();

    var iniciado = false;

    try {
      iniciado = await Nearby().startAdvertising(
        _nomeUsuario,
        _strategy,
        serviceId: _serviceId,
        onConnectionInitiated:
            _aoIniciarConexao,
        onConnectionResult:
            _aoResultadoConexao,
        onDisconnected: _aoDesconectar,
      );
    } catch (erro) {
      if (!_erroJaEstaAnunciando(erro)) {
        rethrow;
      }

      iniciado = true;
    }

    if (!mounted) return;

    setState(() {
      _anunciando = iniciado;
    });
  }

  bool _erroJaEstaAnunciando(Object erro) {
    final texto =
        erro.toString().toUpperCase();

    return texto.contains(
          'STATUS_ALREADY_ADVERTISING',
        ) ||
        texto.contains(
          'ALREADY_ADVERTISING',
        ) ||
        texto.contains(
          'ALREADY STARTED',
        );
  }

  Future<void> _alternarBusca() async {
    setState(() {
      _mensagemErro = null;
    });

    if (_procurando) {
      await Nearby().stopDiscovery();

      if (!mounted) return;

      setState(() {
        _procurando = false;
      });

      return;
    }

    if (!await _pedirPermissoes()) {
      return;
    }

    try {
      final iniciado =
          await Nearby().startDiscovery(
        _nomeUsuario,
        _strategy,
        serviceId: _serviceId,
        onEndpointFound:
            (id, nome, serviceId) {
          if (serviceId != _serviceId) {
            return;
          }

          setState(() {
            final jaExiste =
                _aparelhosEncontrados.any(
              (item) => item.id == id,
            );

            if (!jaExiste) {
              _aparelhosEncontrados.add(
                _AparelhoEncontrado(
                  id: id,
                  nome: nome,
                ),
              );
            }
          });

          _atualizarModalBusca?.call();
        },
        onEndpointLost: (id) {
          setState(() {
            _aparelhosEncontrados
                .removeWhere(
              (item) => item.id == id,
            );
          });

          _atualizarModalBusca?.call();
        },
      );

      if (!mounted) return;

      setState(() {
        _procurando = iniciado;
      });
    } catch (erro) {
      _definirErro(
        'Não foi possível procurar aparelhos: $erro',
      );
    }
  }

  Future<void> _conectar(
    _AparelhoEncontrado aparelho,
  ) async {
    if (_conectando) return;

    try {
      setState(() {
        _conectando = true;
        _mensagemErro = null;
      });

      if (_procurando) {
        await Nearby().stopDiscovery();
      }

      if (_anunciando) {
        await Nearby().stopAdvertising();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _procurando = false;
        _anunciando = false;
      });

      await Nearby().requestConnection(
        _nomeUsuario,
        aparelho.id,
        onConnectionInitiated:
            _aoIniciarConexao,
        onConnectionResult:
            _aoResultadoConexao,
        onDisconnected: _aoDesconectar,
      );
    } catch (erro) {
      _definirErro(
        'Falha ao solicitar conexão. '
        'Toque em Buscar aparelhos e tente novamente. $erro',
      );
    } finally {
      if (mounted) {
        setState(() {
          _conectando = false;
        });
      }
    }
  }

  void _aoIniciarConexao(
    String id,
    ConnectionInfo info,
  ) {
    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Conectar com ${info.endpointName}?',
          ),
          content: Text(
            'Código de confirmação: '
            '${info.authenticationToken}',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();

                await Nearby()
                    .rejectConnection(id);
              },
              child: const Text('Recusar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();

                _aceitarConexao(id, info);
              },
              child: const Text('Aceitar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _aceitarConexao(
    String id,
    ConnectionInfo info,
  ) async {
    setState(() {
      _aparelhosConectados[id] = info;

      _aparelhosEncontrados.removeWhere(
        (item) => item.id == id,
      );

      _conversaSelecionadaId =
          _chaveCelular(id);
    });

    _marcarConversaComoAberta(
      _chaveCelular(id),
    );

    _atualizarModalBusca?.call();

    await Nearby().acceptConnection(
      id,
      onPayLoadRecieved:
          (endpointId, payload) {
        if (payload.type !=
                PayloadType.BYTES ||
            payload.bytes == null) {
          return;
        }

        final texto =
            utf8.decode(payload.bytes!);

        final nome =
            _aparelhosConectados[endpointId]
                    ?.endpointName ??
                'Aparelho';

        final conversaId =
            _chaveCelular(endpointId);

        _processarPacotesRecebidos(
          texto,
          conversaId,
          nome,
        );
      },
      onPayloadTransferUpdate:
          (_, update) {},
    );
  }

  void _aoResultadoConexao(
    String id,
    Status status,
  ) {
    if (status == Status.CONNECTED) {
      setState(() {
        _conectando = false;
      });

      unawaited(
        _reenviarMensagensPendentes(
          _chaveCelular(id),
        ),
      );

      _mostrarMensagem('Conectado.');

      unawaited(
        _garantirDisponibilidade(),
      );

      return;
    }

    if (status == Status.REJECTED) {
      setState(() {
        _aparelhosConectados.remove(id);

        if (_conversaSelecionadaId ==
            _chaveCelular(id)) {
          _conversaSelecionadaId = null;
        }

        _conectando = false;
      });

      _mostrarMensagem(
        'Conexão recusada.',
      );

      unawaited(
        _garantirDisponibilidade(),
      );

      return;
    }

    if (status == Status.ERROR) {
      setState(() {
        _aparelhosConectados.remove(id);

        if (_conversaSelecionadaId ==
            _chaveCelular(id)) {
          _conversaSelecionadaId = null;
        }

        _conectando = false;
      });

      _mostrarMensagem(
        'Erro ao conectar.',
      );

      unawaited(
        _garantirDisponibilidade(),
      );
    }
  }

  void _aoDesconectar(String id) {
    final nome =
        _aparelhosConectados[id]
                ?.endpointName ??
            'Aparelho';

    setState(() {
      _aparelhosConectados.remove(id);

      if (_conversaSelecionadaId ==
          _chaveCelular(id)) {
        _conversaSelecionadaId = null;
      }
    });

    _mostrarMensagem(
      '$nome desconectou.',
    );

    unawaited(
      _garantirDisponibilidade(),
    );
  }

  Future<void> _enviarMensagem() async {
    final texto =
        _mensagemController.text.trim();

    final conversa =
        _conversaSelecionada;

    if (texto.isEmpty ||
        conversa == null) {
      return;
    }

    final mensagemId =
        _novoIdMensagem();

    setState(() {
      _mensagens.add(
        _MensagemChat(
          id: mensagemId,
          conversaId: conversa.id,
          texto: texto,
          remetente: _nomeUsuario,
          enviadaPorMim: true,
          status: MessageStatus.digitada,
        ),
      );

      _mensagemController.clear();
    });

    unawaited(_persistirMensagens());

    final bytes = _codificarMensagem(
      mensagemId,
      texto,
    );

    try {
      await Nearby().sendBytesPayload(
        conversa.deviceId,
        bytes,
      );

      _atualizarStatusMensagem(
        mensagemId,
        MessageStatus.recebida,
      );
    } catch (erro) {
      _definirErro(
        'Não foi possível enviar a mensagem: $erro',
      );
    }
  }

  void _atualizarStatusMensagem(
    String mensagemId,
    MessageStatus status,
  ) {
    if (!mounted) return;

    final index = _mensagens.indexWhere(
      (mensagem) =>
          mensagem.id == mensagemId,
    );

    if (index == -1) return;

    setState(() {
      _mensagens[index] =
          _mensagens[index]
              .copyWith(status: status);
    });

    unawaited(_persistirMensagens());
  }

  void _adicionarMensagemRecebidaAoHistorico(
    _MensagemChat mensagem,
  ) {
    setState(() {
      _mensagens.add(mensagem);
    });

    unawaited(_persistirMensagens());
  }

  void _marcarConversaComoAberta(
    String conversaId,
  ) {
    if (!mounted ||
        !_conversaEstaAberta(
          conversaId,
        )) {
      return;
    }

    var alterou = false;

    for (var i = 0;
        i < _mensagens.length;
        i++) {
      final mensagem = _mensagens[i];

      if (mensagem.conversaId ==
              conversaId &&
          !mensagem.enviadaPorMim &&
          mensagem.status !=
              MessageStatus.aberta) {
        _mensagens[i] =
            mensagem.copyWith(
          status: MessageStatus.aberta,
        );

        alterou = true;

        unawaited(
          _enviarConfirmacaoAbertura(
            conversaId,
            mensagem.id,
          ),
        );
      }
    }

    if (alterou) {
      setState(() {});

      unawaited(
        _persistirMensagens(),
      );
    }
  }

  bool _conversaEstaAberta(
    String conversaId,
  ) {
    return _appEmPrimeiroPlano &&
        _conversaSelecionadaId ==
            conversaId;
  }

  Future<void> _enviarConfirmacaoAbertura(
    String conversaId,
    String mensagemId,
  ) async {
    final conversa =
        _conversaPorId(conversaId);

    if (conversa == null) return;

    final bytes =
        _codificarConfirmacaoAbertura(
      mensagemId,
    );

    await Nearby().sendBytesPayload(
      conversa.deviceId,
      bytes,
    );
  }

  Future<void> _reenviarMensagensPendentes(
    String conversaId,
  ) async {
    final conversa =
        _conversaPorId(conversaId);

    if (conversa == null) return;

    final pendentes = _mensagens
        .where(
          (mensagem) =>
              mensagem.conversaId ==
                  conversaId &&
              mensagem.enviadaPorMim &&
              mensagem.status ==
                  MessageStatus.digitada,
        )
        .toList();

    if (pendentes.isEmpty) {
      return;
    }

    final bytes =
        _codificarLoteMensagens(
      pendentes,
    );

    await Nearby().sendBytesPayload(
      conversa.deviceId,
      bytes,
    );

    for (final mensagem
        in pendentes) {
      _atualizarStatusMensagem(
        mensagem.id,
        MessageStatus.recebida,
      );
    }
  }

  String _chaveCelular(String id) {
    return 'celular:$id';
  }

  List<_Conversa> get _conversas {
    return [
      for (final entry
          in _aparelhosConectados.entries)
        _Conversa(
          id: _chaveCelular(entry.key),
          deviceId: entry.key,
          nome: entry.value.endpointName,
          subtitulo: 'Celular',
          tipo: _TipoConversa.celular,
          icone: Icons.smartphone,
        ),
    ];
  }

  _Conversa? get _conversaSelecionada {
    final id = _conversaSelecionadaId;

    if (id == null) return null;

    return _conversaPorId(id);
  }

  _Conversa? _conversaPorId(String id) {
    for (final conversa in _conversas) {
      if (conversa.id == id) {
        return conversa;
      }
    }

    return null;
  }

  List<_MensagemChat> _mensagensDaConversa(
    String conversaId,
  ) {
    return _mensagens
        .where(
          (mensagem) =>
              mensagem.conversaId ==
              conversaId,
        )
        .toList();
  }

  Future<void> _abrirBuscaCelulares() async {
    if (!_procurando) {
      await _alternarBusca();
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder:
              (context, setModalState) {
            _atualizarModalBusca =
                () => setModalState(() {});

            return _ModalBuscaCelulares(
              aparelhos:
                  _aparelhosEncontrados,
              conectando: _conectando,
              onConectar:
                  (aparelho) async {
                await _conectar(
                  aparelho,
                );

                if (context.mounted &&
                    Navigator.of(context)
                        .canPop()) {
                  Navigator.of(context)
                      .pop();
                }
              },
            );
          },
        );
      },
    );

    _atualizarModalBusca = null;

    if (_procurando) {
      await Nearby().stopDiscovery();

      if (mounted) {
        setState(() {
          _procurando = false;
        });
      }
    }

    if (mounted) {
      await _garantirDisponibilidade();
    }
  }

  void _definirErro(String mensagem) {
    if (!mounted) return;

    setState(() {
      _mensagemErro = mensagem;
    });
  }

  void _mostrarMensagem(
    String mensagem,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(mensagem),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conversa =
        _conversaSelecionada;

    return Scaffold(
      appBar: AppBar(
        leading: conversa == null
            ? null
            : IconButton(
                tooltip: 'Voltar',
                onPressed: () {
                  setState(() {
                    _conversaSelecionadaId =
                        null;
                  });
                },
                icon: const Icon(
                  Icons.arrow_back,
                ),
              ),
        title: Text(
          conversa?.nome ??
              'Chat Bluetooth',
        ),
        actions: [
          PopupMenuButton<_AcaoMenu>(
            onSelected: (acao) {
              switch (acao) {
                case _AcaoMenu.editarNome:
                  _abrirEdicaoNome();

                case _AcaoMenu.buscarCelulares:
                  _abrirBuscaCelulares();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value:
                    _AcaoMenu.editarNome,
                child: ListTile(
                  leading: Icon(
                    Icons.edit,
                  ),
                  title: Text(
                    'Nome do aparelho',
                  ),
                  contentPadding:
                      EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: _AcaoMenu
                    .buscarCelulares,
                child: ListTile(
                  leading: Icon(
                    Icons.smartphone,
                  ),
                  title: Text(
                    'Buscar celulares',
                  ),
                  contentPadding:
                      EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_mensagemErro != null)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  8,
                ),
                child: Text(
                  _mensagemErro!,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .error,
                  ),
                ),
              ),
            Expanded(
              child: conversa == null
                  ? _ListaConversas(
                  conversas: _conversas,
                  mensagens: _mensagens,
                  nomeUsuario: _nomeUsuario,
                  disponivel: _anunciando,
                  onSelecionar: (conversa) {
                        setState(() {
                          _conversaSelecionadaId =
                              conversa.id;
                        });

                        _marcarConversaComoAberta(
                          conversa.id,
                        );
                      },
                    )
                  : _Chat(
                      mensagens:
                          _mensagensDaConversa(
                        conversa.id,
                      ),
                      controller:
                          _mensagemController,
                      conectado: true,
                      onEnviar:
                          _enviarMensagem,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
