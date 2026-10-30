# Storage Atlas — UX, utilidade e qualidade

**Estado:** implementada em v0.3, a pedido do usuário, com identidade visual preservada naquela entrega; a solicitação posterior de v0.4 autoriza redesenhá-la. DESIGN.md registra os controles construídos; VERIFICATION.md registra evidências e limites, incluindo validações que ainda não constituem teste completo de VoiceOver ou de um scan global concluído.

**Método:** Impeccable, Shape/Operate, implementação nativa e revisão funcional independente. A política abaixo orienta o produto; metas de qualidade não equivalem a métricas já comprovadas.

## 1. Propósito e personalidade

O Atlas é uma lupa de armazenamento para quem desenvolve no Mac. Deve ajudar a responder, nesta ordem:

1. Onde o espaço medido está concentrado?
2. Dentro dessa pasta, quais filhos explicam o tamanho?
3. Que tipo de conteúdo é esse e como foi reconhecido?
4. Qual é o próximo passo útil, dentro do escopo de leitura?
5. Quanto dessa visão ainda é desconhecido ou está desatualizado?

A personalidade se manifesta no comportamento: preciso nos números, curioso na exploração, direto nas explicações e cuidadoso com o contexto do usuário. Lembra a navegação, revela relações e admite o que não sabe. Não usa slogans, mascote, pontuações de saúde ou urgência fabricada para dar identidade ao produto.

**Unidade de sucesso:** localizar um consumidor relevante, descer até a causa, entender a evidência e chegar ao caminho real sem se perder ou iniciar outro scan. Quantidade de blocos desenhados não é indicador de utilidade.

## 2. Diagnóstico do que existe

| Área | v0.2 observada no código/evidência | Lacuna que esta especificação resolve |
| --- | --- | --- |
| Exploração | Duplo clique em pasta, subir, Home e menu de ancestrais funcionam na evidência nativa. | Entrar depende de descobrir gestos; falta árvore explícita, histórico e breadcrumb por segmentos. |
| Detalhamento | A projeção pode abrir vários níveis e exibir nomes de hashes no zoom. | A profundidade deve acompanhar uma intenção de exploração; filhos imediatos precisam ser identificáveis. |
| Lista | Mostra maiores arquivos e resultados, com paginação. | Não substitui uma árvore: a consulta usada exclui diretórios. |
| Categorias | Sete categorias, cores e destaque, com regras explicáveis. | Faltam composição por escopo e categorias textuais com totais. Modelos estão misturados com mídia; pasta mista pode aparecer como Other files. |
| Inspeção | Clique abre detalhes com caminho, medidas, evidência e ações. | Inspecionar não deve desmontar o contexto de uma árvore aberta. |
| Confiança | Snapshot parcial, cobertura e alocação desconhecida ficam explícitos. | Preservar essa honestidade em cada nível e distinguir ausência de resultado de falta de acesso. |

As capturas são evidência histórica da v0.2, não uma nova sessão de uso. A entrega anterior passou em revisão visual, mas o pedido atual eleva a exigência de orientação e descoberta das interações.

## 3. Dois eixos de organização

### Localização: a árvore real

A árvore responde **onde**. Seus nós são pastas e arquivos de caminhos canônicos do snapshot. Não reorganizar arquivos em pastas virtuais de categorias dentro dessa árvore.

No nível global, os contornos distinguem áreas reais como Users, Applications, Library e System, quando presentes no índice. Nomes amigáveis podem acompanhar um caminho, nunca ocultar ou alterar sua identidade. Não inventar uma pasta Projetos nem atribuir todos os arquivos de Library a aplicativos específicos.

### Natureza: categorias do conteúdo

Categorias respondem **o que**. São uma leitura transversal da mesma árvore, disponível em um controle compacto com nome, total medido e participação na pasta em foco. Selecionar uma categoria destaca os caminhos correspondentes e oferece resultados; não troca silenciosamente a raiz física nem recalcula a área dos outros blocos.

| Categoria | Conteúdo e subdivisões úteis | Limite da afirmação |
| --- | --- | --- |
| Desenvolvimento | Código, dependências, saídas de build, Git, simuladores e armazenamento de containers; subtipo quando há regra. | Git pode conter trabalho local; containers e simuladores podem conter dados persistentes. |
| Aplicativos | Bundles `.app` e recursos internos. | Não inclui automaticamente todo dado relacionado em Library. |
| Caches | Cache de aplicativo e de downloads de pacotes, quando reconhecidos. | Não significa descartável; downloads e requisitos offline podem importar. |
| Compactados e instaladores | Formatos reconhecidos de arquivo compactado, imagem e instalador. | Não extrair conteúdo nem inferir que o original existe em outro lugar. |
| Modelos e checkpoints | Pesos e checkpoints reconhecidos por extensão ou caminho. | Origem e possibilidade de baixar novamente podem ser desconhecidas. |
| Mídia | Imagens, áudio, vídeo e formatos reconhecidos. | Não inferir propriedade ou uso recente. |
| Documentos | Documentos e formatos de texto reconhecidos. | Não ler conteúdo para classificar. |
| Outros / não classificados | Arquivos sem regra suficiente. | É uma incerteza explícita, não uma recomendação de remoção. |

Modelos e Mídia são separados nos novos scans (classificação v2); snapshots anteriores mantêm a classificação original, indicada no app. Subtipos reutilizam evidência determinística, sem análise de conteúdo ou IA.

Cada arquivo tem **uma categoria primária** para somas. Subtipos/contextos não geram totais adicionais somáveis. Uma pasta pode conter várias categorias: mostrar **Pasta · conteúdo misto**, com composição calculada dos descendentes quando disponível. Não usar o `.other` estrutural de uma pasta como prova de que todos os seus arquivos são desconhecidos. Até calcular a composição, mostrar “Composição não calculada”.

A precedência também deve ser explícita e testada: o conteúdo de um artefato reconhecido conserva seu contexto principal; uma extensão interna não deve desmontar silenciosamente um bundle de Aplicativos em outras categorias. Para arquivos fora desses contextos, aplicar a regra específica sustentada por evidência, depois extensão e por fim Outros. Toda mudança nessa precedência requer versão e testes de reconciliação.

## 4. Espaço de trabalho

```text
[Voltar] [Avançar] [Subir]  Mac › … › code › projeto
[Pastas]   Escopo / total medido   [Categorias]   [Buscar…] [Atualizar]
┌───────────────────────────────────────────────────────────────────┐
│                                                                   │
│                   MAPA DE ARMAZENAMENTO                            │
│                                                                   │
│                         ┌ painel opcional à direita ─────────────┐│
│                         │ Pastas / Resultados / Detalhes         ││
│                         │ conteúdo do modo escolhido             ││
│                         └────────────────────────────────────────┘│
├───────────────────────────────────────────────────────────────────┤
│ Caminho sob o ponteiro · tipo · tamanho    Medição · cobertura      │
└───────────────────────────────────────────────────────────────────┘
```

Wireframe de comportamento; não estabelece uma segunda barra obrigatória nem proporções fictícias de dados. Reutilizar o chrome compacto existente.

- O mapa continua sendo a tela principal. Sem painel aberto, manter pelo menos 85% da área útil no tamanho de referência, excluindo chrome nativo da janela com denominador documentado.
- **Pastas** deve ser um controle nomeado e visível, não uma função escondida em menu de contexto. Abre o painel recolhível à direita, inicialmente fechado, com largura inicial de 324 pontos.
- Um único painel alterna Pastas, Resultados e Detalhes. São modos auxiliares da mesma tela, não três novos destinos principais. Não abrir dois painéis simultâneos nem transformar o mapa em uma faixa estreita.
- O painel sobrepõe o mapa. Abrir, fechar ou trocar de modo não altera as coordenadas de seus blocos. Redimensionar a janela ou entrar em outra pasta pode recalcular o layout.
- No compacto de 960 × 600, usar menu de categorias, breadcrumb comprimido e o mesmo painel único. Caminho completo continua acessível por foco/inspeção.

## 5. Contrato da árvore e do mapa

### Estado compartilhado

Há uma única pasta em foco, um item selecionado, um caminho de navegação, filtros explícitos e um snapshot. Árvore, mapa, breadcrumb e resultados usam esses mesmos identificadores. Expandir uma árvore é um estado separado de entrar em uma pasta.

### Linha da árvore

Cada linha oferece nome, ícone de tipo, tamanho alocado e participação no pai medido. Pastas têm controle de expansão; arquivos não. Ordenar irmãos por tamanho decrescente, com desempate estável por caminho. Quantidade de itens é informação secundária.

O denominador deve ser textual: **“40% desta pasta”**. Só exibir o percentual quando ambos os tamanhos foram medidos e o denominador é positivo. Zero alocado, desconhecido e sem acesso são estados distintos. Uma subpasta incompleta recebe indicação de cobertura parcial.

### Interações previsíveis

| Ação | Resultado |
| --- | --- |
| Clicar no controle de expansão | Carrega e expande somente os filhos daquele nó; mantém a pasta em foco e o mapa. |
| Ativar uma linha de pasta | Entra nela: mapa e breadcrumb passam para essa pasta; árvore destaca o nó e preserva ramos abertos. |
| Ativar uma linha de arquivo | Seleciona o arquivo; destaca seu bloco ou seu contêiner agregado. Ação Detalhes permite inspecioná-lo sem perder a árvore. |
| Clique simples em bloco | Seleciona e evidencia o item. Se Pastas estiver aberto, mantém esse modo e oferece Detalhes; nos demais casos pode abrir a inspeção existente. |
| Duplo clique em pasta ou ação Ver conteúdo | Entra na pasta sem novo scan. A ação nomeada é uma alternativa visível ao gesto. |
| Clique em arquivo no mapa | Permite inspeção; nunca executa ou abre o arquivo automaticamente. |
| Ativar segmento do breadcrumb | Entra nesse ancestral, mantendo a identidade do caminho real. |
| Subir | Entra no pai real, sem confundir com histórico. |
| Voltar / Avançar | Restaura foco, seleção, consulta/escopo/categoria, modo do painel, expansão da árvore e posição da lista anteriores. Não inicia scan. |
| Fechar painel | Mantém foco, seleção e estado de expansão para reabertura. |

O gesto completo pode selecionar antes de entrar; o resultado final do duplo clique é uma única navegação, sem deixar uma inspeção concorrente aberta.

### Profundidade e legibilidade

- Ao entrar em F, seus **filhos imediatos** são as unidades principais de comparação. O maior filho aparece primeiro na árvore e deve ser fácil de identificar no mapa.
- Uma prévia de descendentes só é aceitável sob um contorno cujo ancestral seja legível e ativável. Não saltar vários níveis e apresentar centenas de hashes sem explicar a pasta que os contém.
- Cadeias sem ramificações podem ser compactadas visualmente, mas seus segmentos continuam acessíveis no breadcrumb/árvore. Nenhum caminho é inventado.
- Pacotes e artefatos reconhecidos ficam agregados por padrão; Ver conteúdo permite explorá-los. O pai e seus filhos não contam duas vezes.
- A árvore carrega filhos sob demanda. Grandes listas têm paginação ou virtualização e indicam o que falta carregar. Não criar milhões de linhas SwiftUI de uma vez.
- Rollups têm nome de agrupamento, tamanho e contagem reais. Abrir um rollup revela uma lista explicitamente identificada como conteúdo do pai; não fingir que essa lista contém somente os membros omitidos se a consulta não consegue distingui-los.
- Arquivos com zero alocado permanecem na árvore/lista/busca, sem área fictícia. Caminhos sem acesso podem aparecer como linhas informativas de cobertura, nunca como arquivos de tamanho zero.

### Teclado e acessibilidade

Na árvore, ↑/↓ move entre linhas visíveis; → expande; ← recolhe ou move ao pai; Return entra na pasta ou inspeciona o arquivo. Tab alcança controles nomeados e o foco permanece visível.

Home no mapa retorna à raiz; Backspace no mapa sobe; ⌘↑ sobe; ⌘0 volta ao Mac. ⌘F foca a busca; ⌘\ alterna Pastas; ⌘L abre Resultados; ⌘I abre Detalhes. Esses atalhos novos só serão considerados existentes depois de implementados e verificados. Não capturar edição de texto como navegação.

Escape fecha o popover/painel ativo; em seguida pode limpar busca. Não muda de pasta de surpresa. VoiceOver deve anunciar nome, tipo, tamanho, participação e estado expandido/selecionado. A árvore oferece alternativa completa ao apontamento em blocos pequenos.

## 6. Busca e categorias sem perda de contexto

A busca usa a pasta em foco por padrão, com seletor explícito **Nesta pasta / No Mac**. Na raiz global, o escopo é No Mac. Isso altera o comportamento histórico de v0.2, cuja busca textual cobria sempre o snapshot inteiro.

- A interface mostra escopo, consulta e categoria ativos, com ação clara para limpar.
- A busca destaca sem reordenar ou redimensionar a partição do mapa. Uma categoria mantém esse mesmo contrato.
- Resultados trazem caminho, tamanho, tipo e **Abrir pasta**. Um resultado fora da pasta atual pode ser inspecionado no painel; Abrir pasta navega explicitamente e registra o retorno no histórico.
- Se um resultado está dentro de um bloco agregado, destacar seu contêiner e dizer “Contido em …”. Não sugerir que o contêiner inteiro é a correspondência exata.
- Limpar a busca restaura a mesma navegação. Mudar de pasta mantém o filtro visível e atualiza o escopo indicado; não deixar um filtro invisível explicar um mapa aparentemente vazio.
- Diferenciar “Nenhum resultado neste escopo”, “Lendo índice”, “Pasta sem arquivos medidos” e “Sem acesso”. Em resultado vazio, oferecer limpar filtro ou buscar No Mac.

A área de uma pasta continua usando seu total alocado medido como denominador. Totais de resultados não substituem esse total. Percentuais de categoria mostram sua participação no foco, nunca ocupação do disco inteiro sem dizer isso.

## 7. Política de utilidade

Uma funcionalidade só entra se tiver pergunta concreta, evidência disponível e próximo passo que reduza trabalho.

| Pergunta | Evidência mínima | Próximo passo útil |
| --- | --- | --- |
| Onde está o peso? | Caminho, alocação e participação no pai. | Entrar na pasta ou comparar irmãos. |
| O que explica essa pasta? | Maiores filhos e composição medida. | Descer um nível mantendo o contexto. |
| Que artefato é esse? | Regra/extensão/caminho que sustentam a classificação. | Ler evidência e consequência; revelar o local. |
| Posso recriar isso? | Consequência conhecida e seus limites. | Revisão individual informada; desconhecido quando não há evidência. |
| O que ainda não foi medido? | Estado do scan, limites de acesso e notas retidas. | Inspecionar cobertura; atualizar quando necessário. |

Não aprovar uma função apenas porque produz mais um gráfico, métrica ou página. Preferir ampliar árvore, inspeção e busca antes de criar destinos.

Permanecem fora do escopo: executar limpeza, inferir arquivos não usados, somar suposta economia, atribuir propriedade a apps sem evidência, analisar conteúdo, adicionar serviço externo ou daemon. O planejador de espaço continua adiado; não reaparece como dashboard nesta mudança.

## 8. Política de qualidade

### Correção e confiança — bloqueadores de entrega

- Partição soma exatamente os bytes medidos do foco; fronteiras do pai não somam outra vez.
- Alocação, tamanho lógico, capacidade do volume e eventual recuperação hipotética continuam separados.
- Categoria não pode usar totais de pastas e arquivos simultaneamente. Conteúdo misto não recebe uma categoria uniforme inventada.
- Expansão e navegação usam caminhos canônicos e o mesmo snapshot; preservam não travessia de symlinks, contabilização de hard links e exclusão do índice.
- Falta de acesso e ausência de notas detalhadas ficam explícitas. “Scan concluído” descreve o processo, não prova acesso completo ou bytes recuperáveis.
- Caminhos removidos após a medição são tratados como desatualizados; falhar ao revelar não equivale a arquivo inexistente no snapshot.

### Orientação e resposta — metas para medir, não resultados já obtidos

- Um usuário deve encontrar Pastas e Ver conteúdo sem descobrir duplo clique por tentativa. Em teste de tarefa, localizar um consumidor e sua participação em até 10 segundos é a meta inicial.
- Seleção e acionamento dão feedback perceptível em até 100 ms. Navegar por filhos em índice já disponível tem meta p95 de até 500 ms no Mac de referência; medir com dataset real e declarar cache frio/quente.
- Se a consulta exceder 500 ms, preservar a última visão e indicar qual pasta está carregando. Não mostrar título do novo foco sobre dados antigos sem marcação de transição.
- Busca ampla e scan não bloqueiam entrada, foco ou retorno. Consultas superadas não podem substituir resultados novos. Medir cancelamento efetivo; o SQLite atual só verifica cancelamento entre etapas, não dentro de toda instrução.
- Se uma operação do macOS aguarda acesso, não inventar a causa nem prometer parada instantânea de uma chamada bloqueada. Diferenciar pedido de cancelamento de cancelamento concluído, mantendo a visão disponível e as decisões de privacidade sob controle do usuário.
- Ao atualizar o snapshot, preservar o caminho focado se ainda existir; caso contrário, usar o ancestral existente mais próximo e explicar o retorno. Não saltar silenciosamente para a raiz.

### Leitura e comportamento

- Rótulos essenciais não dependem de cor ou hover. Pastas, arquivos e agrupamentos são distinguíveis antes da inspeção.
- Nome longo pode truncar na comparação; caminho e nome completos continuam disponíveis na inspeção e no acesso assistivo.
- Estados normal, foco, selecionado, carregando, vazio, sem acesso e erro devem ter comportamento definido. Sem elementos com aparência acionável e ação ausente.
- Compacto, teclado e VoiceOver são gates reais. Aprovação de screenshot não substitui teste de tarefa ou acessibilidade.
- Manter linguagem direta e consistente com o idioma do app/sistema; nomes de caminhos permanecem literais. Os exemplos desta especificação usam PT-BR, não atestam tradução da v0.2.

### Assinatura de interação

O cuidado distintivo do Atlas é a continuidade: ao entrar, fica claro o que mudou; ao voltar, o contexto reaparece; ao inspecionar, a proporção permanece; ao desconhecer, a dúvida aparece. Animação só comunica mudança de foco/estado, respeitando Reduce Motion. Não adicionar decoração para compensar navegação fraca.

## 9. Cenários de aceitação

1. **Exploração contínua:** abrir Pastas, expandir uma pasta sem alterar o foco, entrar nela, comparar os maiores filhos e repetir em três níveis. Árvore, breadcrumb e mapa concordam; nenhum scan novo é iniciado.
2. **Retorno:** entrar por mapa e por árvore, usar Voltar, Avançar, Subir e ancestral. Retomar seleção, expansão e posição de lista corretas; Subir e Voltar têm semânticas distintas.
3. **Inspeção com árvore aberta:** selecionar arquivo no mapa, inspecionar e voltar para Pastas sem perder o ramo ou a pasta focada.
4. **Composição mista:** pasta com código, mídia e desconhecidos não aparece como um bloco semanticamente uniforme de Outros. Totais de categorias reconciliam com os arquivos alocados daquele escopo.
5. **Busca contextual/global:** buscar dentro de um projeto; ampliar para No Mac; abrir a pasta de um resultado externo; voltar ao projeto com consulta e contexto recuperados.
6. **Itens difíceis de atingir:** achar arquivo com zero alocado, arquivo fora da projeção e membro de rollup via árvore/lista/busca, com limites do agrupamento explícitos.
7. **Dados incompletos:** exibir snapshot parcial, pasta sem acesso, notas não retidas, query lenta e caminho desatualizado; nenhum vira um zero ou sucesso fictício.
8. **Dataset real:** medir navegação e busca no índice de milhões de arquivos, sem inserir fixtures no mapa como se fossem dados do Mac.
9. **Compacto e teclado:** executar o fluxo principal em 960 × 600 e na janela normal; testar árvore por teclado e anúncios assistivos.
10. **Atualização:** terminar/cancelar refresh preservando uma visão útil e o foco válido. Verificar abertura do cache concluído e Reveal in Finder, limites ainda pendentes na evidência v0.2.

## 10. Ordem de trabalho e limite desta rodada

**P0 — orientação:** modelo compartilhado de navegação/seleção/histórico; árvore lazy com pastas e arquivos; breadcrumb por segmentos; ação Ver conteúdo; sincronização mapa/árvore/painel; distinção de pasta mista e estados desconhecidos. Encerrar com os cenários 1–3, 6–9, correção contábil e execução nativa.

**P1 — entendimento:** composição por categoria do foco, subtipos com evidência, separação Modelos/Mídia, escopo explícito da busca e preservação de foco em refresh. Mudanças em classificação exigem política de versão/migração dos snapshots, testes de filesystem/SQLite e cenários 4–5 e 10. Não reinterpretar silenciosamente categorias antigas como recém-medidas.

A implementação autorizada de v0.3 cobre P0 e P1. Esta especificação complementa REFACTOR_PLAN.md e tem precedência nas regras de árvore, profundidade, busca e composição aqui revisadas. DESIGN.md registra a interface construída; VERIFICATION.md preserva os limites de validação em vez de transformar metas em resultados.


## Evolução visual v0.4

A solicitação posterior do usuário autoriza controles e painéis flutuantes, blocos mais suaves, hierarquia numérica mais clara e transições curtas. Os requisitos de orientação, escopo, estados, árvore, histórico e medição acima continuam vinculantes. Navegação e inspeção não reparticionam o mapa; movimento reduzido desativa o deslocamento/transição autorais. O cabeçalho distingue valor zero medido, tamanho desconhecido e ausência de resultado, e explicita snapshots limitados a pasta. Os valores da árvore profunda permanecem dentro da área visível.
