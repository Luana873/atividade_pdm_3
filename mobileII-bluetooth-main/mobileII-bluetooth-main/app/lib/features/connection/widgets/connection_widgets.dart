part of '../connection_screen.dart';

class _DialogEdicaoNome extends StatefulWidget {
  const _DialogEdicaoNome({required this.nomeInicial});

  final String nomeInicial;

  @override
  State<_DialogEdicaoNome> createState() => _DialogEdicaoNomeState();
}

class _DialogEdicaoNomeState extends State<_DialogEdicaoNome> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.nomeInicial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _salvar() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nome do aparelho'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        maxLength: 32,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'Digite seu nome',
        ),
        onSubmitted: (_) => _salvar(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvar,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _ListaConversas extends StatelessWidget {
  const _ListaConversas({
    required this.conversas,
    required this.mensagens,
    required this.nomeUsuario,
    required this.disponivel,
    required this.onSelecionar,
  });

  final List<_Conversa> conversas;
  final List<_MensagemChat> mensagens;
  final String nomeUsuario;
  final bool disponivel;
  final ValueChanged<_Conversa> onSelecionar;

  @override
  Widget build(BuildContext context) {
    if (conversas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                nomeUsuario,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                disponivel
                    ? 'Disponível para conexão com outros celulares.'
                    : 'Use o menu para buscar dispositivos.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: conversas.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final conversa = conversas[index];

        _MensagemChat? ultimaMensagem;

        for (final mensagem in mensagens) {
          if (mensagem.conversaId == conversa.id) {
            ultimaMensagem = mensagem;
          }
        }

        return ListTile(
          leading: CircleAvatar(
            child: Icon(conversa.icone),
          ),
          title: Text(
            conversa.nome,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            ultimaMensagem?.texto ?? conversa.subtitulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onSelecionar(conversa),
        );
      },
    );
  }
}

class _ModalBuscaCelulares extends StatelessWidget {
  const _ModalBuscaCelulares({
    required this.aparelhos,
    required this.conectando,
    required this.onConectar,
  });

  final List<_AparelhoEncontrado> aparelhos;
  final bool conectando;
  final ValueChanged<_AparelhoEncontrado> onConectar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.65,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text(
                  'Buscar celulares',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _ListaAparelhos(
              aparelhos: aparelhos,
              conectando: conectando,
              onConectar: onConectar,
            ),
          ),
        ],
      ),
    );
  }
}

class _ListaAparelhos extends StatelessWidget {
  const _ListaAparelhos({
    required this.aparelhos,
    required this.conectando,
    required this.onConectar,
  });

  final List<_AparelhoEncontrado> aparelhos;
  final bool conectando;
  final ValueChanged<_AparelhoEncontrado> onConectar;

  @override
  Widget build(BuildContext context) {
    if (aparelhos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Nenhum aparelho encontrado.',
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: aparelhos.length,
      itemBuilder: (context, index) {
        final aparelho = aparelhos[index];

        return ListTile(
          leading: const Icon(Icons.smartphone),
          title: Text(aparelho.nome),
          subtitle: Text(aparelho.id),
          trailing: IconButton(
            tooltip: 'Conectar',
            onPressed: conectando
                ? null
                : () => onConectar(aparelho),
            icon: conectando
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.link),
          ),
        );
      },
    );
  }
}

class _Chat extends StatelessWidget {
  const _Chat({
    required this.mensagens,
    required this.controller,
    required this.conectado,
    required this.onEnviar,
  });

  final List<_MensagemChat> mensagens;
  final TextEditingController controller;
  final bool conectado;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: mensagens.isEmpty
              ? const Center(
                  child: Text(
                    'Conecte um aparelho para iniciar o chat.',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: mensagens.length,
                  itemBuilder: (context, index) {
                    final mensagem = mensagens[index];

                    final alinhamento = mensagem.enviadaPorMim
                        ? Alignment.centerRight
                        : Alignment.centerLeft;

                    final cor = mensagem.enviadaPorMim
                        ? Theme.of(context)
                            .colorScheme
                            .primaryContainer
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest;

                    return Align(
                      alignment: alinhamento,
                      child: Container(
                        constraints: const BoxConstraints(
                          maxWidth: 420,
                        ),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              mensagem.remetente,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(mensagem.texto),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                mensagem.status.rotulo,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: conectado,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Digite uma mensagem',
                  ),
                  onSubmitted: conectado
                      ? (_) => onEnviar()
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Enviar',
                onPressed: conectado
                    ? onEnviar
                    : null,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}