# Guia rápido

Instale o hefesto e escolha uma de duas formas de trabalhar: **uma sessão** ou **quatro sessões**. Toda decisão —
aprovar um plano, responder uma pergunta, pedir mudanças — é um formulário numa sessão só, a orchestrator; nada é
copiado entre sessões. Linux e macOS. O guia completo, em inglês, é o [`install.md`](install.md).

*In English: [`quickstart.md`](quickstart.md).*

> **Como digitar os comandos.** O Claude Code dá aos comandos de um plugin o nome do plugin, então todo comando do
> hefesto é digitado com o prefixo `hefesto:`: `/hefesto:hef.orchestrate`, `/hefesto:hef.ship`, `/hefesto:hef.doctor`.
> Digite `/hefesto:` no prompt para ver todos. Todo comando desta documentação está escrito assim, pronto para colar.

## 1. Antes de começar

O hefesto roda dentro do [Claude Code](https://code.claude.com/docs/en/setup) (o comando `claude`). Ele também
precisa de `git` e `jq`, e do `gh` para pull requests e quadros no GitHub. As sessões rodam dentro do sandbox do
Claude Code, que no Linux precisa de `bubblewrap` e `socat`; no macOS o sandbox já vem no sistema.

| | Instale as ferramentas |
|---|---|
| **macOS** | `xcode-select --install` (git), depois `brew install jq gh` |
| **Ubuntu / Debian** | `sudo apt install git jq bubblewrap socat`, e o gh em [cli.github.com](https://cli.github.com) |
| **Fedora** | `sudo dnf install git jq bubblewrap socat gh` |
| **Arch** | `sudo pacman -S git jq bubblewrap socat github-cli` |

Depois entre no gh uma vez: `gh auth login`. No macOS tudo roda com o `/bin/bash` 3.2 e as ferramentas BSD que vêm
no sistema; não precisa do bash do Homebrew.

## 2. Instalar ou atualizar o hefesto

O mesmo comando instala e atualiza o hefesto. Feche todas as janelas do Claude Code e, num terminal normal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/install.sh) --lang pt
```

Ele mostra o que encontrou e os passos que recomenda, e pergunta sobre cada um; aperte Enter para aceitar. Ele nunca
usa `sudo`, e copia todo arquivo que substitui para `~/hefesto-old/` antes. No fim aparece
`Tudo certo: todos os perfis rodam o hefesto <versão>.` Opções: `--version v9.3.0` (uma release), `--dry-run`
(mostra o plano, não muda nada), `--help`.

Confira no Claude Code com `/hefesto:hef.doctor`.

**Depois de atualizar**, em todo projeto preparado para o hefesto, rode a preparação de novo na pasta principal dele
e reinicie as sessões do Claude Code dele:

```bash
bash ~/.claude-framework/hooks/hefesto-setup.sh            # acrescente --lanes num projeto de quatro sessões
```

As primeiras linhas de uma sessão de um projeto de quatro sessões avisam quando for preciso; numa sessão só, o
`/hefesto:hef.orchestrate` para e diz o comando. O que mudou entre as releases: [Notas de atualização](#notas-de-atualização)
abaixo.

## 3. Uma sessão ou quatro sessões?

|  | **Uma sessão** | **Quatro sessões** |
|---|---|---|
| Para | experimentos, projetos pequenos, uma feature por vez | um fluxo contínuo de RFCs e correções |
| Sessões abertas | uma: a orchestrator | a orchestrator + planner, builder e deployer |
| Quem roda as etapas | sessões em segundo plano que a orchestrator abre | as três sessões de etapa, chamadas pela orchestrator |
| Preparação | `hefesto-setup.sh` | `hefesto-setup.sh --lanes` |

Comece com uma sessão; o mesmo projeto pode ganhar as outras três depois (rode a preparação com `--lanes`).

## 4. Prepare o projeto

O hefesto trabalha num repositório git com um remoto no GitHub: a builder abre pull requests com o `gh` e a deployer
acompanha a CI deles.

**Um projeto que você já tem:**

1. Abra um terminal na pasta principal dele (o checkout principal, não um worktree).
2. Se ele ainda não tem `.specify/`, abra o `claude` ali e rode `/hefesto:hef.init` (a pasta de specs e um esqueleto
   de constituição), depois `/hefesto:hef.constitution` (as regras do seu projeto). Faça commit da `.specify/`.
3. Opcional: `/hefesto:hef.baseline` escreve specs para o código que já existe, antes de você mudá-lo.
4. Um quadro que você já tem (uma pasta `tasks/`, um arquivo de backlog, um GitHub Project) é adotado, não
   substituído: o primeiro `/hefesto:hef.orchestrate` lista o que encontrou e pergunta qual usar.
5. Um repositório com vários apps (`backend/`, `apps/web/`)? Dê a cada um a sua `.specify/`; veja o
   [`install.md`](install.md) §7, passo 15.

**Um projeto novo:**

```bash
mkdir meuproduto && cd meuproduto
git init -b main && git commit --allow-empty -m "start"
gh repo create meuproduto --private --source . --push
```

Abra o `claude` nessa pasta, rode `/hefesto:hef.init`, depois `/hefesto:hef.constitution`, e faça commit da
`.specify/`. O primeiro `/hefesto:hef.orchestrate` cria o quadro (uma pasta `tasks/` e o `.claude/project-status.json`).

## 5. Uma sessão

1. **Prepare o projeto uma vez** — num terminal, na pasta principal do projeto:
   ```bash
   bash ~/.claude-framework/hooks/hefesto-setup.sh
   ```
   `--check` diz se a preparação ainda está em dia, e `--help` lista as opções.
2. **Abra a sessão** — com `claude`, ou qualquer wrapper que repasse os argumentos do claude:
   ```bash
   claude --name meuproduto-orchestrator
   ```
3. **Confira:** `/hefesto:hef.orchestrate` — ele mostra a preparação e cria o quadro se não houver um.
4. **Entregue algo:** `/hefesto:hef.ship "exportar pedidos em CSV"` (ou `/hefesto:hef.ship ABC-12` para um item que
   já está no quadro). Uma feature passa por um brainstorm com você, vira uma RFC e é planejada em segundo plano; o
   plano chega para você num formulário (`"plan_review": "human"`, que a configuração de quadro criada pelo hefesto
   define); ela é construída, conferida por outra sessão, e o pull request é acompanhado até a CI ficar verde. Uma
   correção de bug vai direto para a builder.
5. **Faça o merge** do pull request no GitHub com **Create a merge commit** e rode `/hefesto:hef.orchestrate` uma
   vez: ele registra o merge.

## 6. Quatro sessões

1. **Prepare o projeto uma vez** — num terminal, na pasta principal do projeto:
   ```bash
   bash ~/.claude-framework/hooks/hefesto-setup.sh --lanes
   ```
2. **Abra e dê nome às quatro sessões**, cada uma no seu terminal, todas com o mesmo perfil do Claude Code. Os nomes
   vêm da pasta do projeto, ou de `"lane_prefix": "meuproduto"` em `orchestrate` no `.claude/project-status.json`:
   ```bash
   claude --name meuproduto-orchestrator
   claude --name meuproduto-planner
   claude --name meuproduto-builder
   claude --name meuproduto-deployer
   ```
   Um mapa explícito também serve: `"lanes": {"orchestrator": "…", "plan": "…", "build": ["…", "…"], "deploy": "…"}`.
   Rode a preparação de novo depois de mudar os nomes.
3. **Inicie cada sessão de etapa uma vez:** `/hefesto:hef.orchestrate --stage plan` na planner, `--stage build` na
   builder, `--stage deploy` na deployer. Daí em diante elas esperam a campainha da orchestrator, e cada uma
   narra a sua execução enquanto ela acontece (`· /hefesto:hef.spec`, `· write …/plan.md`, `· run: go test ./...`,
   `■ done`). As três etapas andam juntas; para mais builders, `"max_builders": 2` em `orchestrate` e abra
   também a `meuproduto-builder2`.
   **Sessões que fazem o trabalho elas mesmas:** acrescente `"lane_mode": "interactive"` em `orchestrate`, ou por
   etapa (`{"build": "interactive"}`). Cada sessão de etapa passa a planejar, construir ou publicar na própria
   conversa, no worktree do item, sem sessão em segundo plano e sem gasto além do da própria sessão. Dá para conversar
   com ela no meio da tarefa, e depois de compactar ou reiniciar ela retoma o que tem nas mãos. Abra essas sessões
   com `--permission-mode acceptEdits`, para que as edições no worktree não peçam permissão; a orchestrator fica no
   modo padrão.
4. **Na orchestrator:** `/hefesto:hef.orchestrate` — ele confere a preparação e encontra as três sessões.
5. **Mande as RFCs:** `/hefesto:hef.ship ABC-12` para um item com a sua RFC no quadro (`rfc: docs/rfcs/ABC-12.md`
   abaixo do título), ou `/hefesto:hef.ship "<ideia>"`. A orchestrator chama a planner; quando um plano fica pronto
   ela pede a sua aprovação, depois chama a builder, depois a deployer. Aprovações, respostas e pedidos de
   mudança acontecem todos na orchestrator; o merge você faz no GitHub.

As sessões de etapa compilam e testam por meio do `hooks/lane-build.sh <comando>` (por exemplo
`lane-build.sh go test ./...`): ele dá ao build um cache gravável próprio dentro do sandbox. Um build rodado sem ele
falha no cache somente-leitura.

## No dia a dia

- **Decisões** chegam como formulários na orchestrator. Responder um roda o comando certo, e o Claude
  Code mostra o pedido de permissão dele — confirme. Esse pedido é a sua assinatura; rode a orchestrator no
  modo de permissão padrão (num projeto de quatro sessões ela avisa nos modos auto, dontAsk ou bypassPermissions).
- **RFCs** ficam em `docs/rfcs/<ID>.md`, uma por item, ligadas por uma linha `rfc:`. Se uma RFC muda depois
  que o plano foi aprovado, a builder para e a orchestrator pede que você alinhe o plano.
- **A linha de status** mantém a sua (perfil, modelo, pasta…) e acrescenta `ctx 45% · 90k/200k` (o contexto
  usado, os tokens no contexto sobre o tamanho da janela); abaixo, uma linha por execução em segundo plano
  (`▶ implement FAB-1 · 4m`) e por decisão que espera por você (`⏸ FAB-3 · plan approval`).
- **Compacte** quando a linha de status de uma sessão disser `/compact`, com o prompt próprio dela
  ([`performance.md`](performance.md), "Compact prompts per pane"). `/clear` só para trabalho sem relação.
  `context.compact_at` no `.claude/project-status.json` define quando ela avisa (40% por padrão; por sessão, ou 0
  para nunca).
- **Gasto e rede.** Cada execução em segundo plano pode gastar até `orchestrate.usd_cap` (US$ 20 por padrão), e um
  quadro até `daily_usd_cap` (US$ 100) por dia; o trabalho feito numa sessão interativa não tem limite. Uma execução
  em segundo plano não acessa nenhum endereço da rede que não esteja listado: para trabalho com dependências,
  acrescente `"allowed_domains": ["registry.npmjs.org"]` em `orchestrate` (só nomes públicos).
- **Um GitHub Project como quadro.** As sessões podem tirar seus itens de um GitHub Project: cada issue do
  repositório que está no Project é um item (`BC-42` para a issue #42), e o Status dela é a coluna. O
  `/hefesto:hef.orchestrate` oferece os Projects do repositório quando você adota um quadro, e o `/hefesto:hef.ship`
  adiciona issues a ele; com `"publish": true` em `orchestrate`, cada mudança de estado move o cartão. Issues de
  contas de fora do time esperam você lê-las primeiro. Preparação e escopos: [`install.md`](install.md) §7, passo 14.
- **Vários apps num repositório** (`spec_roots`): o `/hefesto:hef.ship` pergunta qual app é dono de um item novo, e a
  orchestrator pergunta por todo item que não diz; cada item é planejado e construído na pasta do seu app.
  [`install.md`](install.md) §7, passo 15.
- **Se algo parecer errado**, rode `/hefesto:hef.doctor`, copie a mensagem exata e mande para o seu líder.

**Só em projetos de quatro sessões** — isto é feito por uma sessão de etapa:

- **Ações das sessões.** Qualquer coisa que uma sessão deva fazer por você (fazer o merge do PR #726 no SHA certo,
  cortar uma release, publicar em stg, rodar um backfill, reiniciar um container) é um formulário na orchestrator.
  Peça à orchestrator com as suas palavras. Ela escreve os passos, os heads exatos, as verificações de parada e os
  comandos, e mostra tudo. Você responde **Approve** e confirma o pedido de permissão. A sessão faz exatamente isso,
  sem nenhum pedido na tela dela, e avisa quando terminou ou onde parou. Um head que mudou, ou qualquer coisa fora do
  combinado, volta para você como um novo formulário. A linha de status mostra cada uma que espera por você
  (`⏸ DET-7-A2 · action: merge PR #726`).
- **Receitas de deploy.** Escreva um deploy uma vez, por ambiente, em `orchestrate.deploy.recipes` no
  `.claude/project-status.json`: passos em ordem, cada um com um título e os seus comandos, com `{version}`, `{sha}` e
  `{env}` preenchidos quando você pede. Um passo com `"expect": "{version}"` para a execução quando a versão que ele
  lê de volta é outra.
  ```json
  "deploy": { "recipes": { "stg": { "steps": [
    { "title": "deploy",  "commands": ["/usr/bin/ssh deploy@stg-host ./deploy.sh {version}"] },
    { "title": "version", "commands": ["/usr/bin/curl -fsS https://stg-host/api/version/"], "expect": "{version}" } ] } } }
  ```
  Um comando que sai do sandbox (ssh, docker, um host interno) é acrescentado uma vez com
  `hefesto-setup.sh --lanes --unsandboxed-command "/usr/bin/ssh deploy@stg-host"` (um caminho absoluto); acrescente a
  checagem com curl do mesmo jeito quando `stg-host` for interno. Depois diga "deploy stg 1.4.2" na orchestrator: ela
  mostra um formulário com todos os comandos escritos, você aprova, e a deployer roda exatamente esses, passo a passo,
  sem nenhum pedido na tela dela. Mudar a receita depois não muda nada que já foi aprovado.
- **Trens de release.** Para promover vários repositórios juntos (um quadro externo com um mapa `repos`, e um modelo
  `branches` em cada repositório), nomeie-os em `orchestrate.deploy.trains`
  (`"app": {"repos": ["api", "ui"], "order": ["api", "ui"]}`), abra um PR de promoção por repositório contra a branch
  do ambiente, e peça à orchestrator "promote app to stg". É um formulário só; a deployer vai repositório por
  repositório nessa ordem — o estado do PR, as verificações, depois o merge — e uma falha num repositório para tudo
  antes do próximo.
- **Merges pela deployer.** Com `"merge_by": "lane"` em `orchestrate`, o formulário de merge ganha **Merge**: a
  deployer relê o PR (limpo, CI verde, head ainda o SHA que você viu), roda as suas `orchestrate.merge.checks` (por
  exemplo `changelog-check.sh -C {repo_path} placement --base origin/{base}`, por caminho absoluto) e faz o merge
  com um merge commit exatamente nesse head e o registra. Um head que mudou, uma verificação vermelha ou um conflito
  voltam para você como um formulário. Um merge por repositório de cada vez. O padrão, `"merge_by": "person"`, não
  muda: o merge você faz no GitHub.

**Segurança num parágrafo.** As sessões mantêm o sandbox do Claude Code, e os comandos dentro dele rodam sem
perguntar. Fora dele rodam só os ajudantes do próprio hefesto, o `gh` e os comandos que você acrescentou com
`--unsandboxed-command`, cada um chamado como um comando simples; num projeto de quatro sessões esses comandos
acrescentados rodam só como uma ação aprovada. O ledger, as suas aprovações e o registro de qual sessão é qual ficam
em `~/.cache/hefesto`, onde nenhum comando com sandbox e nenhuma edição de arquivo chega. Os comandos que registram as
suas decisões rodam só na orchestrator, atrás de um pedido de permissão, e um `gh pr merge` nunca roda sem uma ação
aprovada ou sem o seu pedido. Uma sessão lê textos de itens e RFCs escritos por outras pessoas, então leia cada
formulário e cada pedido antes de responder.

## Notas de atualização

Rode o comando de instalação, depois a preparação em cada projeto (seção 2). Além disso:

- **Para a 9.3:** os comandos são escritos `/hefesto:hef.<nome>` em todo lugar, do jeito que o Claude Code os
  resolve (o nome sem o prefixo nunca funcionou para um plugin). Um repositório agora pode ter vários apps, cada um
  com a sua `.specify/` (`spec_roots`, [`install.md`](install.md) §7, passo 15); um repositório sem isso funciona como
  antes. Num repositório de um app só, um comando de spec rodado numa subpasta agora usa a `.specify/` do topo em vez
  de criar uma ali.
- **Para a 9.2:** rode a preparação com `--lanes` de novo e reinicie as sessões: ela cria o cache de build das
  sessões, e as sessões de etapa compilam por meio do `hooks/lane-build.sh`. Os hooks de um worker lançado não rodam
  mais o código do projeto fora do sandbox. Um GitHub Project pode ser o quadro.
- **Para a 9.1, num projeto de quatro sessões:** uma sessão agora roda um comando que sai do sandbox só como uma ação
  aprovada — todo comando da lista `--unsandboxed-command` da preparação e qualquer `excludedCommands` nas suas outras
  configurações do Claude Code. O `gh` (as leituras continuam livres) e os ajudantes do próprio hefesto não mudam. Se
  uma sessão usava um desses comandos sozinha na 9.0, agora ele é negado com uma mensagem que diz qual: peça uma ação
  à orchestrator (uma receita transforma uma ação repetida num formulário só).
