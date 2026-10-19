# Guia rápido

Do zero até quatro sessões cuidando do ciclo de desenvolvimento, em seis passos. Linux e macOS, como
vêm de fábrica. O guia completo, em inglês, é o [`install.md`](install.md). Para o Claude te guiar
pelos mesmos passos, abra o Claude Code num projeto e digite:
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

## 3. Preparar o projeto (uma vez por repositório)

O jeito fácil: no Claude Code, dentro do projeto, digite o pedido do `SETUP.md` acima. O Claude confere
o projeto, junta numa mensagem só as decisões que são do seu líder e depois escreve a configuração num
pull request. O que ele prepara:

1. `/hef.init`, que cria a pasta `.specify/` das especificações e planos.
2. O quadro: `tasks/TODO.md`, `DOING.md`, `DONE.md` e `BACKLOG.md`. Cada item é um título com um código
   e um nome, seguido de umas linhas dizendo o que se quer:
   ```markdown
   ## ABC-12 — Exportar pedidos em CSV

   A página de pedidos ganha um botão "Exportar CSV" com as colunas que aparecem na tela.
   ```
   O prefixo do código tem duas ou mais letras maiúsculas ou dígitos, começando por uma letra. As
   sessões só pegam trabalho do `TODO.md`; o que só uma pessoa pode fazer vai para o `BACKLOG.md`.
3. `.claude/project-status.json`, com o quadro, os limites de gasto, o comando que roda os testes do
   projeto e `"plan_first": true` (o modelo está no [`SETUP.md`](../SETUP.md), passo 4c).
4. No GitHub: merge commit permitido e squash e rebase desligados (o hefesto reconhece um merge
   encontrando a branch dentro da branch de integração), e a branch onde o trabalho se integra protegida
   (pull request obrigatório antes do merge). Uma branch que não seja a `main` (por exemplo `dev`) é declarada em
   `branches` ([`install.md`](install.md) §7, passo 12).

Faça o merge do pull request de setup e atualize a pasta principal do projeto (`git pull`) antes de
seguir: as sessões leem o quadro dessa pasta.

## 4. Abrir as quatro sessões

Cada uma no seu terminal, dentro da pasta principal do projeto. Troque `<repo>` pelo nome da pasta:

```bash
claude --name <repo>-orchestrator --permission-mode default --settings '{"sandbox":{"enabled":false}}'
claude --name <repo>-plan         --permission-mode default --settings '{"sandbox":{"enabled":false}}'
claude --name <repo>-build        --permission-mode default --settings '{"sandbox":{"enabled":false}}'
claude --name <repo>-deploy       --permission-mode default --settings '{"sandbox":{"enabled":false}}'
```

`--permission-mode default` mantém as janelas de permissão, e algumas das etapas que dependem de uma
pessoa são essas janelas. O sandbox fica desligado nessas quatro porque elas abrem outras sessões; as
sessões que elas abrem rodam com sandbox.

## 5. Ligar as etapas

As sessões não recebem ordens umas das outras. Cada uma trabalha quando o comando dela roda, e o trabalho
passa de uma para outra pelo ledger. Rode isto uma vez em cada:

| Sessão | Rode uma vez | O que ela faz depois |
|---|---|---|
| plan | `/loop 15m /hef.orchestrate --stage plan` | A cada 15 minutos: especificação, plano, revisão e tarefas do próximo item novo |
| build | `/loop 15m /hef.orchestrate` | O próximo item planejado: implementado, conferido por outra sessão, pull request aberto |
| deploy | `/loop 15m /hef.orchestrate --stage deploy` | O próximo pull request: a CI acompanhada e corrigida até ficar pronto para o merge |
| orchestrator | `/hef.status` quando quiser | O quadro e os números de entrega. As sessões das etapas rodam `/hef.orchestrate`; esta não |

- Cada volta pega um item e respeita o `usd_cap` e o `daily_usd_cap`. Roda uma sessão em segundo plano
  por repositório de cada vez: uma etapa que encontra o repositório ocupado avisa e tenta na próxima volta.
- `"plan_first": true` impede a etapa build de pegar um item que a etapa plan ainda não planejou.
- Para ver o estado de cada item na sessão orchestrator: `bash ~/.claude-framework/hooks/ledger.sh list --active`
  (rodando) e `… list --blocked` (esperando). Use a pasta onde o hefesto está instalado, se não for
  `~/.claude-framework`.
- Aperte Esc para parar um loop. Você também pode digitar os mesmos comandos à mão.

## 6. No dia a dia

1. Coloque os itens no `tasks/TODO.md`.
2. Quando um item espera por uma pessoa, o `list --blocked` mostra (e toda sessão mostra esses itens ao
   abrir). O que fazer depende do tipo:
   - `human:clarify` ou `human:plan-review` no item `ABC-12`: o planejador deixou as perguntas na pasta
     do próprio item. Abra o Claude Code lá (`cd .claude/worktrees/ABC-12 && claude`) e rode
     `/hef.clarify` (perguntas) ou `/hef.review` (revisão do plano). Depois, na pasta do projeto,
     `bash ~/.claude-framework/hooks/ledger.sh unblock ABC-12`. A etapa plan retoma o item na próxima volta.
   - qualquer outro (`verdict`, `stall`, `budget`, `conflict`, `ci`, `human:intake`): fale com o seu líder.
3. Faça você o merge de cada pull request no GitHub, com **Create a merge commit**. Nenhuma sessão faz
   merge. Na volta seguinte, a etapa deploy confere que o merge aconteceu de verdade, registra e segue com
   o item: não há nada para digitar. Depois de um merge com squash ou rebase essa conferência não enxerga
   o merge: fale com o seu líder, que registra com `ledger.sh unblock <id> --merge-sha <o commit do merge>`.
4. Entre um item e outro, ou quando a conversa de uma sessão ficar longa, rode o `/compact` próprio dela
   ([`performance.md`](performance.md), "Compact prompts per pane").
5. Se algo parecer errado, rode `/hef.doctor`, copie a mensagem exata e mande para o seu líder.
