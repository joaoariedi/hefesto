# Guia rápido

Do zero até trabalhar com o hefesto: instale, confira e escolha uma de duas formas de trabalhar. Linux e
macOS, como vêm de fábrica. O guia completo, em inglês, é o [`install.md`](install.md). Para o Claude te
guiar pelos mesmos passos, abra o Claude Code num projeto e digite:
``Rode `curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/SETUP.md` e siga as instruções.``

*In English: [`quickstart.md`](quickstart.md).*

## 1. Instalar ou atualizar

Feche todas as janelas do Claude Code. Num terminal normal (fora do Claude Code), rode:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/install.sh) --lang pt
```

Aperte Enter em cada pergunta para aceitar a recomendação. No fim aparece
`Tudo certo: todos os perfis rodam o hefesto <versão>`. Ele nunca apaga nada; as cópias ficam em
`~/hefesto-old/`.

## 2. Conferir

1. Abra o Claude Code dentro de um projeto git, não na sua pasta pessoal: `cd ~/seu-projeto && claude`.
2. Nas primeiras linhas aparece `hefesto <versão> hooks loaded from …`. Versão antiga quer dizer que a
   janela estava aberta durante a atualização: feche todas e abra de novo.
3. Digite `/hef.doctor`. Ele deve mostrar `status: RUNNING_MATCHES_CLONE`.

## 3. Escolher como trabalhar

| | **Simples** — uma sessão | **Pipeline** — quatro sessões |
|---|---|---|
| Serve para | experimentos, protótipos, projetos pequenos, uma pessoa | uma fila de RFCs esperando para virar código, um trem contínuo de features, várias pessoas |
| Você roda | `/hef.agent <o que você quer>` numa sessão | quatro etapas que passam os itens adiante por um ledger |
| Preparar | `/hef.init` uma vez | um quadro, uma pasta de RFCs, uma configuração, ajustes no GitHub (passo 5) |

Na dúvida, comece pelo Simples; o projeto pode passar para o Pipeline depois.

## 4. Simples: uma sessão

1. No Claude Code, dentro do projeto: `/hef.init` (uma vez).
2. Para cada mudança: `/hef.agent <o que você quer>`. Ele mede o trabalho e escolhe o caminho mais curto e
   seguro — um ajuste rápido, uma especificação leve, ou a cadeia completa especificação → plano → revisão →
   tarefas → implementação → verificação — e para sempre que precisa da sua resposta.
3. `/hef.pr` abre o pull request; você faz o merge.
4. Compactação: numa pausa natural dentro de uma tarefa longa, `/compact` (o prompt geral do
   [`performance.md`](performance.md)); entre tarefas sem relação, `/clear`.

É só isso no modo Simples. O resto deste guia é o Pipeline.

## 5. Pipeline: preparar o projeto (uma vez por repositório)

O jeito fácil é o pedido do `SETUP.md` acima: o Claude confere o projeto, junta numa mensagem só as
decisões do seu líder e depois escreve a configuração num pull request. O que ele prepara:

1. `/hef.init`, que cria a pasta `.specify/` das especificações e planos.
2. O quadro: `tasks/TODO.md`, `DOING.md`, `DONE.md`, `BACKLOG.md`. Cada item é um título com um código e um
   nome (`## ABC-12 — Exportar pedidos em CSV`), seguido de umas linhas — e, para trabalho planejado, a sua
   RFC (passo 6). O prefixo do código tem duas ou mais letras maiúsculas ou dígitos, começando por uma
   letra. As etapas só pegam trabalho do `TODO.md`; o que só uma pessoa pode fazer vai para o `BACKLOG.md`.
3. `.claude/project-status.json` — o quadro, os limites de gasto, o comando dos testes e três ajustes de
   que as quatro etapas dependem (o modelo completo está no [`SETUP.md`](../SETUP.md), passo 4c):
   - `"plan_first": true` — a etapa build nunca pega um item que a etapa plan ainda não planejou;
   - `"plan_review": "human"` — todo plano espera a aprovação de uma pessoa (passo 8);
   - `"context": {"compact_at": {"orchestrator": 40, "plan": 50, "build": 0, "deploy": 0}}` — quando a
     linha de status de cada etapa avisa para compactar (0 = nunca).
4. No GitHub: merge commit permitido e squash e rebase desligados, e a branch onde o trabalho se integra
   protegida (pull request obrigatório). Uma branch que não seja a `main` (por exemplo `dev`) é declarada
   em `branches` ([`install.md`](install.md) §7, passo 12).

Faça o merge do pull request de setup e depois `git pull` na pasta principal do projeto antes de seguir.

## 6. Pipeline: RFCs

Uma RFC é o desenho de onde uma feature é construída: um arquivo por item do quadro, `docs/rfcs/<ID>.md`
(outra pasta com `orchestrate.rfc_dir`). O item aponta para ela com uma linha abaixo do título:

```markdown
## ABC-12 — Exportar pedidos em CSV
rfc: docs/rfcs/ABC-12.md
```

- **Escrita por outra pessoa:** ela coloca a RFC pronta ali e cria o item.
- **Escrita com o hefesto:** na etapa plan, `/hef.brainstorm <a ideia> para ABC-12` — ele salva o desenho
  aprovado como a RFC desse item e acrescenta a linha `rfc:`.

O planejador em segundo plano da etapa plan especifica a partir da RFC — sem novas decisões de desenho,
cada requisito da RFC vira um requisito da especificação que cita a sua seção, as perguntas em aberto da
RFC voltam para você como perguntas — e planeja e escreve as tarefas. Se a RFC mudar depois que o plano
foi aprovado, a etapa build recusa o item até uma pessoa alinhar o plano e aprovar de novo.

## 7. Pipeline: abrir as quatro etapas

Cada uma no seu terminal, dentro da pasta principal do projeto:

```bash
bash ~/.claude-framework/hooks/lane-launch.sh orchestrator
bash ~/.claude-framework/hooks/lane-launch.sh plan
bash ~/.claude-framework/hooks/lane-launch.sh build
bash ~/.claude-framework/hooks/lane-launch.sh deploy
```

(Use a pasta onde o hefesto está instalado, se não for `~/.claude-framework`.) Cada etapa abre como
`<repo>-<etapa>`, no modo de permissão padrão, com o sandbox desligado (as etapas abrem sessões em segundo
plano, que rodam com sandbox) e uma lista de permissões só com os ajudantes do próprio hefesto: o trabalho
de rotina roda sem perguntas, enquanto qualquer coisa que libere ou reescreva uma decisão de uma pessoa — e
qualquer coisa inesperada — continua perguntando a você. A linha de status mostra o medidor de contexto;
`--keep-statusline` mantém a sua.

Depois, uma vez em cada:

| Etapa | Rode uma vez | O que ela faz depois |
|---|---|---|
| orchestrator | `/hef.status` quando quiser | O quadro e os números de entrega; suas aprovações e merges acontecem aqui. Ela pode iniciar qualquer etapa: `/hef.orchestrate --stage plan\|build\|deploy`, ou `--stage all` para uma volta de recuperação de cada (a sessão fica ocupada enquanto rodam) |
| plan | `/loop 15m /hef.orchestrate --stage plan` | O próximo item novo: especificação a partir da RFC, plano, revisão, tarefas — e então espera a sua aprovação |
| build | `/loop 15m /hef.orchestrate` | O próximo item aprovado: implementado, conferido por outra sessão, pull request aberto |
| deploy | `/loop 15m /hef.orchestrate --stage deploy` | O próximo pull request: a CI acompanhada e corrigida até ficar pronto; depois do seu merge, o merge registrado |

- Roda uma sessão em segundo plano por repositório de cada vez: uma etapa que encontra o repositório
  ocupado avisa e tenta na próxima volta. Cada volta respeita o `usd_cap` e o `daily_usd_cap`.
- Um loop expira 7 dias depois de começar: inicie de novo toda semana. Aperte Esc para parar um.
- Estado de cada item, na orchestrator: `bash ~/.claude-framework/hooks/ledger.sh list --active` (rodando)
  e `… list --blocked` (esperando).

## 8. Pipeline: no dia a dia

1. Coloque os itens (e as suas RFCs) no quadro.
2. **Aprove cada plano.** Um item esperando `human:plan-approval` tem a especificação, o plano e as tarefas
   na própria pasta, `.claude/worktrees/<ID>`. Leia — reescreva ali se quiser diferente — e então, na
   orchestrator:
   ```bash
   bash ~/.claude-framework/hooks/ledger.sh unblock ABC-12 --reviewed-by-human --by "Seu Nome"
   ```
   Ele pede permissão toda vez, e o seu nome fica registrado no item.
3. **Responda às perguntas do planejador.** `human:clarify` ou `human:plan-review` num item: abra o Claude
   Code na pasta dele (`cd .claude/worktrees/ABC-12 && claude`), rode `/hef.clarify` (perguntas) ou
   `/hef.review` (um plano que o revisor não fechou), depois `ledger.sh unblock ABC-12`. Qualquer outro
   bloqueio: fale com o seu líder.
4. **Faça o merge** de cada pull request você mesmo, com **Create a merge commit**. A etapa deploy registra
   o merge na volta seguinte. Depois de um merge com squash ou rebase ela não enxerga o merge: o seu líder
   registra com `ledger.sh unblock <id> --merge-sha <sha>`.
5. **Compacte** quando a linha de status de uma etapa avisar, com o prompt próprio dela
   ([`performance.md`](performance.md), "Compact prompts per pane"). As etapas em loop guardam pouco além
   do que está em disco: deixe-as em 0 e a compactação automática do Claude Code cuida delas. `/clear` só
   para trabalho sem relação ou uma conversa que deu errado.
6. Se algo parecer errado, rode `/hef.doctor`, copie a mensagem exata e mande para o seu líder.
