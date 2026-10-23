# Guia rápido

Instale o hefesto e escolha uma de duas formas de trabalhar. Toda decisão — aprovar um plano, responder
uma pergunta, pedir mudanças — é um formulário numa sessão só, a orchestrator; nada é copiado entre
sessões. Linux e macOS. O guia completo, em inglês, é o [`install.md`](install.md).

*In English: [`quickstart.md`](quickstart.md).*

## 1. Instalar

Feche todas as janelas do Claude Code. Num terminal normal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/install.sh) --lang pt
```

Aperte Enter em cada pergunta. No fim aparece `Tudo certo: todos os perfis rodam o hefesto <versão>`.

|  | **Uma sessão** | **Quatro sessões** |
|---|---|---|
| Para | experimentos, projetos pequenos, uma feature por vez | um fluxo contínuo de RFCs |
| Sessões | uma: a orchestrator | a orchestrator + planner, builder e deployer |
| Quem roda as etapas | sessões em segundo plano que a orchestrator abre | as três sessões de etapa, chamadas pela orchestrator |

Comece com uma sessão; o mesmo projeto pode ganhar as outras três depois.

## 2. Uma sessão

1. **Prepare o projeto uma vez** — num terminal, na pasta principal do projeto:
   ```bash
   bash ~/.claude-framework/hooks/hefesto-setup.sh
   ```
2. **Abra a sessão** — com `claude`, ou qualquer wrapper que repasse os argumentos do claude:
   ```bash
   claude --name meurepo-orchestrator          # ou: claude-profile trabalho --name meurepo-orchestrator
   ```
3. **Confira:** `/hef.orchestrate` — ele mostra a preparação e cria o quadro se não houver um.
4. **Entregue algo:** `/hef.ship "exportar pedidos em CSV"` (ou `/hef.ship ABC-12` para um item que já está
   no quadro). Uma feature passa por um brainstorm com você, vira uma RFC e é planejada em segundo plano;
   você aprova o plano num formulário; ela é construída, conferida por outra sessão, e o pull request é
   acompanhado até a CI ficar verde. Uma correção de bug vai direto para o builder.
5. **Faça o merge** do pull request no GitHub com **Create a merge commit** e rode `/hef.orchestrate` uma
   vez: ele registra o merge.

## 3. Quatro sessões

1. **Prepare o projeto uma vez** — num terminal, na pasta principal do projeto:
   ```bash
   bash ~/.claude-framework/hooks/hefesto-setup.sh --lanes
   ```
2. **Abra e dê nome às quatro sessões**, cada uma no seu terminal, todas com o mesmo perfil:
   ```bash
   claude --name meurepo-orchestrator
   claude --name meurepo-planner
   claude --name meurepo-builder
   claude --name meurepo-deployer
   ```
3. **Inicie cada sessão de etapa uma vez:** `/hef.orchestrate --stage plan` na planner, `--stage build` na
   builder, `--stage deploy` na deployer. Daí em diante elas esperam a campainha da orchestrator, e cada uma
   narra a sua execução enquanto ela acontece (`· /hef.spec`, `· write …/plan.md`, `· run: go test ./...`,
   `■ done`). As três etapas andam juntas; para mais builders, `"max_builders": 2` em `orchestrate` e abra
   também a `meurepo-builder2`.
   **Sessões que fazem o trabalho elas mesmas:** acrescente `"lane_mode": "interactive"` em `orchestrate`, ou por
   etapa (`{"build": "interactive"}`). Cada sessão de etapa passa a planejar, construir ou publicar na própria
   conversa, no worktree do item, sem sessão em segundo plano e sem gasto além do da própria sessão. Dá para conversar
   com ela no meio da tarefa, e depois de compactar ou reiniciar ela retoma o que tem nas mãos. Abra essas sessões
   com `--permission-mode acceptEdits`, para que as edições no worktree não peçam permissão; a orchestrator fica no
   modo padrão.
4. **Na orchestrator:** `/hef.orchestrate` — ele confere a preparação e encontra as três sessões.
5. **Mande as RFCs:** `/hef.ship ABC-12` para um item com a sua RFC no quadro (`rfc: docs/rfcs/ABC-12.md`
   abaixo do título), ou `/hef.ship "<ideia>"`. A orchestrator chama a planner; quando um plano fica pronto
   ela pede a sua aprovação, depois chama a builder, depois a deployer. Aprovações, respostas e pedidos de
   mudança acontecem todos na orchestrator; o merge você faz no GitHub.

## No dia a dia

- **Decisões** chegam como formulários na orchestrator. Responder um roda o comando certo, e o Claude
  Code mostra o pedido de permissão dele — confirme. Esse pedido é a sua assinatura; rode a orchestrator no
  modo de permissão padrão (ela avisa se não estiver).
- **RFCs** ficam em `docs/rfcs/<ID>.md`, uma por item, ligadas por uma linha `rfc:`. Se uma RFC muda depois
  que o plano foi aprovado, a builder para e a orchestrator pede que você alinhe o plano.
- **A linha de status** mantém a sua (perfil, modelo, pasta…) e acrescenta `ctx 45% · 90k/200k` (o contexto
  usado, os tokens no contexto sobre o tamanho da janela); abaixo, uma linha por execução em segundo plano
  (`▶ implement FAB-1 · 4m`) e por decisão que espera por você (`⏸ FAB-3 · plan approval`).
- **Ações das sessões.** Qualquer coisa que uma sessão deva fazer por você (fazer o merge do PR #726 no SHA certo,
  cortar uma release, publicar em stg, rodar um backfill, reiniciar um container) é um formulário na orchestrator.
  Peça à orchestrator com as suas palavras. Ela escreve os passos, os heads exatos, as verificações de parada e os
  comandos, e mostra tudo. Você responde **Approve** e confirma o pedido de permissão. A sessão faz exatamente isso,
  sem nenhum pedido na tela dela, e avisa quando terminou ou onde parou. Um head que mudou, ou qualquer coisa fora do
  combinado, volta para você como um novo formulário. A linha de status mostra cada uma que espera por você
  (`⏸ DET-7-A2 · action: merge PR #726`).
- **Os nomes das sessões** vêm do projeto: `"lane_prefix": "meuproduto"` em `orchestrate` (sessões
  `meuproduto-orchestrator`, `-planner`, `-builder`, `-deployer`), ou um mapa explícito `"lanes": {"orchestrator":
  "…", "plan": "…", "build": ["…", "…"], "deploy": "…"}`. Rode a preparação de novo depois de mudar.
- **Compacte** quando a linha de status de uma sessão disser `/compact`, com o prompt próprio dela
  ([`performance.md`](performance.md), "Compact prompts per pane"). `/clear` só para trabalho sem relação.
- **Gasto e rede.** Cada execução em segundo plano pode gastar até `orchestrate.usd_cap` (US$ 20 por padrão), e
  um repositório até `daily_usd_cap` (US$ 100) por dia. Uma execução em segundo plano não acessa nenhum
  endereço da rede que não esteja listado: para trabalho com dependências, acrescente
  `"allowed_domains": ["registry.npmjs.org"]` em `orchestrate` no `.claude/project-status.json`.
- **Um quadro que você já tem** é adotado, não substituído: sem configuração ainda, o `/hef.orchestrate` lista o
  que o projeto usa (uma pasta `tasks/`, um arquivo de backlog, um repositório no GitHub) e pergunta qual usar.
- **Depois de atualizar o hefesto**, rode o comando de preparação de novo (as primeiras linhas de uma
  sessão avisam quando for preciso).
- **Se algo parecer errado**, rode `/hef.doctor`, copie a mensagem exata e mande para o seu líder.

**Segurança num parágrafo.** As sessões mantêm o sandbox do Claude Code, e os comandos dentro dele rodam sem
perguntar. Fora dele rodam só os ajudantes do próprio hefesto e o `gh`, cada um chamado como um comando simples. O
ledger, as suas aprovações e o registro de qual sessão é qual ficam em `~/.cache/hefesto`, onde nenhum comando com
sandbox e nenhuma edição de arquivo chega. Os comandos que registram as suas decisões rodam só na orchestrator, atrás
de um pedido de permissão, e um `gh pr merge` nunca roda sem uma ação aprovada ou sem o seu pedido. Uma sessão lê
textos de itens e RFCs escritos por outras pessoas, então leia cada formulário e cada pedido antes de responder.
