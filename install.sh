#!/usr/bin/env bash
#
# Hefesto installation wizard — install or upgrade hefesto in one command:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/install.sh)
#   bash ~/.claude-framework/install.sh            # or from a clone you already reviewed
#
# It inspects the machine, prints what it found and the steps it recommends, asks about each step
# (Enter accepts the recommendation), runs them, and verifies every profile from its plugin registry.
# Spec: .specify/specs/install-wizard/ (the plan's "Plan review 2026-10-13" section is the contract).
#
# Safety, because the target user is a junior engineer who presses Enter at every question:
# - it never deletes: a file it replaces is copied to ~/hefesto-old/<ts>/<profile>/ first;
# - it never runs sudo and refuses to run as root;
# - it never forces: a dirty or diverged clone stops it, with the reason;
# - it never writes through a symlink (a symlinked rules/ or CLAUDE.md belongs to someone's dotfiles);
# - without a terminal it refuses rather than silently taking every default (--yes is the opt-in).
#
# Portable to macOS /bin/bash 3.2: no associative arrays, no ${v,,}, no mapfile, no `set -u` (an
# empty array is an error under it before bash 4.4). Lists are newline-separated strings.
#
# The whole body is functions and `main "$@"` is the LAST line: a download cut off half-way defines
# a few functions and runs nothing. tests/smoke.sh also relies on that to source the functions.

ID="hefesto@hefesto"
OLD_ID="ai-development-framework@ai-development-framework"
GUIDE="https://github.com/joaoariedi/hefesto/blob/main/docs/install.md"
QUICKSTART="https://github.com/joaoariedi/hefesto/blob/main/docs/quickstart"   # .md, or .pt-BR.md in Portuguese

init_globals() {
  YES=0; DRY=0; LNG=""; PROFILE_ARGS=""; VERSION_ARG=""
  REPO_URL="${HEFESTO_REPO_URL:-https://github.com/joaoariedi/hefesto.git}"
  BK="$HOME/hefesto-old/$(date +%Y%m%d-%H%M%S)"; BACKED=""
  TIMEOUT=""; CLONE=""; CLONE_STATE=""; CLONE_VER=""; CLONE_BRANCH=""
  LATEST=""; TARGET=""; REC_MAIN=0; STEPS=""; PARTIAL=""
  FOUND=""; CANDIDATES=""; CHOSEN=""; OLD_IN=""; REPOINT=""; TAGS=""; LEGACY_BLOBS=""; CMD_BLOBS=""
  DO_BACKUP=0; DO_OLD=0; DO_CLONE=0; DO_RULES=0; DO_CMD=0; DO_REPOINT=0
}

# --- Messages ---------------------------------------------------------------------------------
# Two case tables (bash 3.2 has no associative arrays). {1} {2} {3} are filled by msg(); a table
# entry is never used as a printf format, so a path with a % in it prints as itself.
msg_keys() {
  echo "title found_header f_clone_absent f_clone f_dirty_no f_latest f_profiles f_prof_ver f_prof_none
  f_prof_unchosen f_old_none f_old_plugin f_legacy_file f_legacy_link plan_header why st_backup
  st_oldplugin st_use_tag st_stay_main st_clone st_update st_profiles st_rules st_claudemd why_backup
  why_oldplugin why_tag why_main why_clone why_update why_profiles why_rules why_claudemd q_step q_profile
  q_legacy hint_yes hint_no ans_again auto_yes dry_auto skipped skipped_profile run_header dry_done
  dry_later already_current reinstall_same keep_old_mkt rules_link file_link_skip cmd_current
  mine_exists legacy_cmds legacy_stow legacy_stop verify_header col_profile col_version col_enabled
  w_yes w_no all_good verify_failed next_header next_restart next_line next_doctor next_sessions next_guide
  backup_note root in_claude missing_tools hint_mac hint_linux hint_claude hint_claude_local
  hint_alias gh_missing home_ro not_writable no_tty tty_eof bad_flag bad_lang bad_version
  need_value bad_profile clone_not_git clone_remote clone_dirty main_diverged no_remote no_tags
  bad_json clone_needed no_profiles step_failed not_updated usage f_legacy_maybe f_prof_other
  st_repoint why_repoint mkt_not_dir orphan_commit no_such_tag clone_tmp legacy_unstow dry_checkout_note partial_left"
}

msg_en() {
  case "$1" in
    title) echo "Hefesto installer" ;;
    found_header) echo "What I found" ;;
    f_clone_absent) echo "  Clone      {1} — not there yet, I will download it" ;;
    f_clone) echo "  Clone      {1} — version {2}, on {3}, {4}" ;;
    f_dirty_no) echo "no local changes" ;;
    f_latest) echo "  Latest     {1}" ;;
    f_profiles) echo "  Profiles" ;;
    f_prof_ver) echo "hefesto {1}" ;;
    f_prof_none) echo "hefesto not installed" ;;
    f_prof_unchosen) echo "    {1}  (found, not used with --yes; add --profile {1})" ;;
    f_old_none) echo "  Old setup  nothing found" ;;
    f_old_plugin) echo "  Old setup  the old plugin ai-development-framework, in {1}" ;;
    f_legacy_file) echo "  Old file   {1}" ;;
    f_legacy_link) echo "  Old link   {1} -> {2}" ;;
    plan_header) echo "The plan — {1} steps. Each one is a question; Enter accepts the recommendation." ;;
    why) echo "     why: {1}" ;;
    st_backup) echo "Back up the files I will change, into {1}" ;;
    st_oldplugin) echo "Remove the old plugin ai-development-framework" ;;
    st_use_tag) echo "Use the latest release, {1}" ;;
    st_stay_main) echo "Stay on main (it is ahead of {1})" ;;
    st_clone) echo "Download hefesto into {1}" ;;
    st_update) echo "Update {1} to the chosen version" ;;
    st_profiles) echo "Install or update the plugin in {1} profile(s)" ;;
    st_rules) echo "Copy hefesto's rules into each profile's rules/ folder" ;;
    st_claudemd) echo "Install hefesto's CLAUDE.md (yours stays, as CLAUDE.md.mine)" ;;
    why_backup) echo "you can copy anything back from there" ;;
    why_oldplugin) echo "it is hefesto's old name; keeping both loads everything twice" ;;
    why_tag) echo "a tested release (answer n to use main, the development branch)" ;;
    why_main) echo "the release tag is older than what you have (answer n to switch to it)" ;;
    why_clone) echo "the plugin is installed from this folder" ;;
    why_update) echo "every profile copies the plugin from this folder" ;;
    why_profiles) echo "each profile runs its own copy of the plugin" ;;
    why_rules) echo "a plugin cannot ship rules; a rule you changed is backed up first" ;;
    why_claudemd) echo "it describes the agents and commands; yours is still loaded, through an import" ;;
    q_step) echo "{1}. {2}?" ;;
    q_profile) echo "{1}. Install or update hefesto in {2}?" ;;
    q_legacy) echo "Continue anyway? Every command and agent would load twice." ;;
    hint_yes) echo "[Y/n]" ;;
    hint_no) echo "[y/N]" ;;
    ans_again) echo "Please answer y (yes) or n (no)." ;;
    auto_yes) echo "--yes: taking every recommended answer." ;;
    dry_auto) echo "--dry-run: showing what the recommended answers would do. Nothing will change." ;;
    skipped) echo "  step {1} skipped" ;;
    skipped_profile) echo "  {1} skipped" ;;
    run_header) echo "Working" ;;
    dry_done) echo "Dry run finished: nothing was changed." ;;
    dry_later) echo "  (the rules and CLAUDE.md come from the clone; I compare them once it is downloaded)" ;;
    already_current) echo "  {1} already runs hefesto {2}" ;;
    reinstall_same) echo "  same version {1} but a different commit: reinstalling (plugin update keys off the version)" ;;
    keep_old_mkt) echo "  kept the marketplace ai-development-framework in {1}: its folder is the hefesto clone. To remove it: CLAUDE_CONFIG_DIR={1} claude plugin marketplace remove ai-development-framework" ;;
    rules_link) echo "  {1} is a link (dotfiles?): I leave it alone. Copy the rules there yourself if you want them." ;;
    file_link_skip) echo "  {1} is a link: I leave it alone." ;;
    cmd_current) echo "  {1} is already hefesto's" ;;
    mine_exists) echo "  {1} already exists, so I leave {2} alone. Merge them by hand, then run me again." ;;
    legacy_cmds) echo "These files are from an old install. Move them out of the way (nothing is deleted):" ;;
    legacy_stow) echo "Some are links from a stow install. Undo it with:  cd {1} && stow -D {2}" ;;
    f_legacy_maybe) echo "  Old file?  {1} (possibly hefesto's: there is no clone yet to compare it with)" ;;
    f_prof_other) echo "    {1} uses another hefesto folder: {2}" ;;
    st_repoint) echo "Point {1} profile(s) at {2}" ;;
    why_repoint) echo "a profile that reads another folder never gets this update (its marketplace file is backed up first)" ;;
    mkt_not_dir) echo "  The hefesto marketplace in {1} is a {2} source, not a folder; I use the default clone folder." ;;
    orphan_commit) echo "{1} has a commit that is on no branch ({2}). A checkout would orphan it. Keep it first:  git -C {1} branch keep-{2}" ;;
    no_such_tag) echo "--version {1} is not a release. Available: {2} (or main)." ;;
    clone_tmp) echo "  (downloading into {1} first; it gets its real name once complete)" ;;
    legacy_unstow) echo "{1} is a link: unstow the package that owns it." ;;
    partial_left) echo "{1} is an unfinished download from this run. Nothing uses it; you can delete it." ;;
    dry_checkout_note) echo "  (note: the rules, CLAUDE.md and commit comparisons below use the clone as it is now, before the update)" ;;
    legacy_stop) echo "Stopped before installing. Move the old files, then run the wizard again." ;;
    verify_header) echo "Check" ;;
    col_profile) echo "Profile" ;;
    col_version) echo "Version" ;;
    col_enabled) echo "Enabled" ;;
    w_yes) echo "yes" ;;
    w_no) echo "no" ;;
    all_good) echo "All good: every profile runs hefesto {1}." ;;
    verify_failed) echo "Not every profile runs hefesto {1}. Read the messages above, or ask for help with /hef.doctor." ;;
    next_header) echo "Next steps" ;;
    next_restart) echo "  1. Restart Claude Code (close every session and open it again)." ;;
    next_line) echo "  2. At the start of a session, look for the line: hefesto {1} hooks loaded from …" ;;
    next_doctor) echo "  3. Run /hef.doctor in a session: it checks the whole install." ;;
    next_sessions) echo "  4. Set up a project and open the four sessions: {1}" ;;
    next_guide) echo "  5. The full guide: {1}" ;;
    backup_note) echo "Backups of the files I changed: {1}" ;;
    root) echo "Please do not run this as root (or with sudo). Run it as your normal user." ;;
    in_claude) echo "This runs inside a Claude Code session. Please run it in a normal terminal." ;;
    missing_tools) echo "Install what is missing above, then run the wizard again. Nothing was changed." ;;
    hint_mac) echo "Missing: {1}. Install it with:  brew install {1}" ;;
    hint_linux) echo "Missing: {1}. Install it with your package manager, e.g.  sudo apt install {1}  (or dnf / pacman)" ;;
    hint_claude) echo "Missing: claude (Claude Code). Install it: https://docs.claude.com/en/docs/claude-code/setup" ;;
    hint_claude_local) echo "  claude is in {1} but that folder is not on your PATH. Add it:  export PATH=\"{1}:\$PATH\"" ;;
    hint_alias) echo "  If claude works in your terminal, it may be an alias; the wizard needs it on PATH." ;;
    gh_missing) echo "Tip: gh (the GitHub CLI) is not installed. Hefesto works without it; some commands use it." ;;
    home_ro) echo "I cannot write to {1}. Is this a sandbox? Run the wizard in a normal terminal." ;;
    not_writable) echo "I cannot write to {1}. Fix its permissions, or leave it out." ;;
    no_tty) echo "No terminal to ask questions in. Run it in a terminal, or add --yes to accept every recommendation." ;;
    tty_eof) echo "No answer (end of input). Stopped; nothing more was changed." ;;
    bad_flag) echo "Unknown option: {1}. See --help." ;;
    bad_lang) echo "--lang must be en or pt, not {1}." ;;
    bad_version) echo "--version must be a tag like v7.9.2, or main — not {1}." ;;
    need_value) echo "{1} needs a value. See --help." ;;
    bad_profile) echo "--profile {1} is not a Claude Code profile folder (it must exist, and not be a clone or a backup)." ;;
    clone_not_git) echo "{1} exists but is not a git clone. Move it away, or point HEFESTO_CLONE_DIR somewhere else." ;;
    clone_remote) echo "{1} is a clone of {2}, not of hefesto. I will not touch it." ;;
    clone_dirty) echo "{1} has local changes. I stop here and leave it untouched. See them with:  git -C {1} status" ;;
    main_diverged) echo "{1}: your main has commits that are not on origin/main. Fix it by hand (git -C {1} log origin/main..main), then run me again." ;;
    no_remote) echo "I cannot reach {1}. Check your network, then run me again." ;;
    no_tags) echo "{1} has no release tags (v*)." ;;
    bad_json) echo "{1} is not valid JSON. Fix it (or restore it) before installing; I will not overwrite it." ;;
    clone_needed) echo "Without the clone there is nothing to install. Stopped; nothing was changed." ;;
    no_profiles) echo "No profile chosen, so there is nothing to install." ;;
    step_failed) echo "This step failed:  {1}  — I stopped here. The output above says why." ;;
    not_updated) echo "{1} reports hefesto {2} after the step, not {3}. Stopped." ;;
    usage) printf '%s\n' "Usage: install.sh [options]" "" \
      "Installs or upgrades hefesto: clone, plugin in each profile, rules and CLAUDE.md." \
      "It shows what it found and the plan, then asks about each step (Enter = recommended)." "" \
      "  --yes             accept every recommendation without asking" \
      "  --dry-run         show the plan and the commands; change nothing" \
      "  --lang en|pt      language (default: from LANG)" \
      "  --profile <dir>   a profile to install into (repeatable)" \
      "  --version <v>     a release tag (v7.9.2) or main" \
      "  --help            this help" ;;
  esac
}

msg_pt() {
  case "$1" in
    title) echo "Instalador do Hefesto" ;;
    found_header) echo "O que encontrei" ;;
    f_clone_absent) echo "  Clone      {1} — ainda não existe, vou baixar" ;;
    f_clone) echo "  Clone      {1} — versão {2}, em {3}, {4}" ;;
    f_dirty_no) echo "sem mudanças locais" ;;
    f_latest) echo "  Mais nova  {1}" ;;
    f_profiles) echo "  Perfis" ;;
    f_prof_ver) echo "hefesto {1}" ;;
    f_prof_none) echo "hefesto não instalado" ;;
    f_prof_unchosen) echo "    {1}  (encontrado, não usado com --yes; adicione --profile {1})" ;;
    f_old_none) echo "  Antigo     nada encontrado" ;;
    f_old_plugin) echo "  Antigo     o plugin antigo ai-development-framework, em {1}" ;;
    f_legacy_file) echo "  Arquivo    {1}" ;;
    f_legacy_link) echo "  Link       {1} -> {2}" ;;
    plan_header) echo "O plano — {1} passos. Cada um é uma pergunta; Enter aceita a recomendação." ;;
    why) echo "     por quê: {1}" ;;
    st_backup) echo "Fazer backup dos arquivos que vou mudar, em {1}" ;;
    st_oldplugin) echo "Remover o plugin antigo ai-development-framework" ;;
    st_use_tag) echo "Usar a versão mais nova, {1}" ;;
    st_stay_main) echo "Ficar na main (ela está à frente de {1})" ;;
    st_clone) echo "Baixar o hefesto em {1}" ;;
    st_update) echo "Atualizar {1} para a versão escolhida" ;;
    st_profiles) echo "Instalar ou atualizar o plugin em {1} perfil(is)" ;;
    st_rules) echo "Copiar as regras do hefesto para a pasta rules/ de cada perfil" ;;
    st_claudemd) echo "Instalar o CLAUDE.md do hefesto (o seu fica, como CLAUDE.md.mine)" ;;
    why_backup) echo "você pode copiar qualquer coisa de volta de lá" ;;
    why_oldplugin) echo "é o nome antigo do hefesto; manter os dois carrega tudo duas vezes" ;;
    why_tag) echo "uma versão testada (responda n para usar a main, o ramo de desenvolvimento)" ;;
    why_main) echo "a tag da versão é mais antiga do que a sua (responda n para mudar para ela)" ;;
    why_clone) echo "o plugin é instalado a partir desta pasta" ;;
    why_update) echo "cada perfil copia o plugin desta pasta" ;;
    why_profiles) echo "cada perfil roda a sua própria cópia do plugin" ;;
    why_rules) echo "um plugin não consegue trazer regras; uma regra que você mudou ganha backup antes" ;;
    why_claudemd) echo "ele descreve os agentes e comandos; o seu continua carregado, por um import" ;;
    q_step) echo "{1}. {2}?" ;;
    q_profile) echo "{1}. Instalar ou atualizar o hefesto em {2}?" ;;
    q_legacy) echo "Continuar mesmo assim? Cada comando e agente carregaria duas vezes." ;;
    hint_yes) echo "[S/n]" ;;
    hint_no) echo "[s/N]" ;;
    ans_again) echo "Responda s (sim) ou n (não), por favor." ;;
    auto_yes) echo "--yes: aceitando todas as respostas recomendadas." ;;
    dry_auto) echo "--dry-run: mostrando o que as respostas recomendadas fariam. Nada vai mudar." ;;
    skipped) echo "  passo {1} pulado" ;;
    skipped_profile) echo "  {1} pulado" ;;
    run_header) echo "Executando" ;;
    dry_done) echo "Simulação concluída: nada foi mudado." ;;
    dry_later) echo "  (as regras e o CLAUDE.md vêm do clone; comparo depois de baixá-lo)" ;;
    already_current) echo "  {1} já roda o hefesto {2}" ;;
    reinstall_same) echo "  mesma versão {1} mas outro commit: reinstalando (o plugin update olha só a versão)" ;;
    keep_old_mkt) echo "  mantive o marketplace ai-development-framework em {1}: a pasta dele é o clone do hefesto. Para remover: CLAUDE_CONFIG_DIR={1} claude plugin marketplace remove ai-development-framework" ;;
    rules_link) echo "  {1} é um link (dotfiles?): não mexo nele. Copie as regras para lá você mesmo, se quiser." ;;
    file_link_skip) echo "  {1} é um link: não mexo nele." ;;
    cmd_current) echo "  {1} já é o do hefesto" ;;
    mine_exists) echo "  {1} já existe, então não mexo em {2}. Junte os dois à mão e rode de novo." ;;
    legacy_cmds) echo "Estes arquivos são de uma instalação antiga. Tire-os do caminho (nada é apagado):" ;;
    legacy_stow) echo "Alguns são links de uma instalação com stow. Desfaça com:  cd {1} && stow -D {2}" ;;
    f_legacy_maybe) echo "  Arquivo?   {1} (talvez do hefesto: ainda não há clone para comparar)" ;;
    f_prof_other) echo "    {1} usa outra pasta do hefesto: {2}" ;;
    st_repoint) echo "Apontar {1} perfil(is) para {2}" ;;
    why_repoint) echo "um perfil que lê outra pasta nunca recebe esta atualização (o arquivo de marketplaces ganha backup antes)" ;;
    mkt_not_dir) echo "  O marketplace hefesto em {1} é uma fonte {2}, não uma pasta; uso a pasta padrão do clone." ;;
    orphan_commit) echo "{1} tem um commit fora de qualquer branch ({2}). Um checkout o deixaria órfão. Guarde-o antes:  git -C {1} branch keep-{2}" ;;
    no_such_tag) echo "--version {1} não é uma versão publicada. Disponíveis: {2} (ou main)." ;;
    clone_tmp) echo "  (baixando primeiro em {1}; ganha o nome certo quando terminar)" ;;
    legacy_unstow) echo "{1} é um link: desfaça o stow do pacote que é dono dele." ;;
    partial_left) echo "{1} é um download incompleto desta execução. Nada o usa; você pode apagá-lo." ;;
    dry_checkout_note) echo "  (nota: as regras, o CLAUDE.md e as comparações de commit abaixo usam o clone como está agora, antes de atualizar)" ;;
    legacy_stop) echo "Parei antes de instalar. Mova os arquivos antigos e rode o instalador de novo." ;;
    verify_header) echo "Conferência" ;;
    col_profile) echo "Perfil" ;;
    col_version) echo "Versão" ;;
    col_enabled) echo "Ativo" ;;
    w_yes) echo "sim" ;;
    w_no) echo "não" ;;
    all_good) echo "Tudo certo: todos os perfis rodam o hefesto {1}." ;;
    verify_failed) echo "Nem todo perfil roda o hefesto {1}. Leia as mensagens acima, ou peça ajuda com /hef.doctor." ;;
    next_header) echo "Próximos passos" ;;
    next_restart) echo "  1. Reinicie o Claude Code (feche todas as sessões e abra de novo)." ;;
    next_line) echo "  2. No início de uma sessão, procure a linha: hefesto {1} hooks loaded from …" ;;
    next_doctor) echo "  3. Rode /hef.doctor numa sessão: ele confere a instalação inteira." ;;
    next_sessions) echo "  4. Prepare um projeto e abra as quatro sessões: {1}" ;;
    next_guide) echo "  5. O guia completo (em inglês): {1}" ;;
    backup_note) echo "Backups dos arquivos que mudei: {1}" ;;
    root) echo "Não rode isto como root (nem com sudo). Rode como o seu usuário normal." ;;
    in_claude) echo "Isto está rodando dentro de uma sessão do Claude Code. Rode num terminal normal." ;;
    missing_tools) echo "Instale o que falta acima e rode o instalador de novo. Nada foi mudado." ;;
    hint_mac) echo "Falta: {1}. Instale com:  brew install {1}" ;;
    hint_linux) echo "Falta: {1}. Instale com o seu gerenciador de pacotes, ex.  sudo apt install {1}  (ou dnf / pacman)" ;;
    hint_claude) echo "Falta: claude (Claude Code). Instale: https://docs.claude.com/en/docs/claude-code/setup" ;;
    hint_claude_local) echo "  o claude está em {1} mas essa pasta não está no PATH. Adicione:  export PATH=\"{1}:\$PATH\"" ;;
    hint_alias) echo "  Se o claude funciona no seu terminal, talvez seja um alias; o instalador precisa dele no PATH." ;;
    gh_missing) echo "Dica: o gh (a CLI do GitHub) não está instalado. O hefesto funciona sem ele; alguns comandos o usam." ;;
    home_ro) echo "Não consigo escrever em {1}. Isto é um sandbox? Rode o instalador num terminal normal." ;;
    not_writable) echo "Não consigo escrever em {1}. Corrija as permissões, ou deixe-o de fora." ;;
    no_tty) echo "Não há terminal para fazer perguntas. Rode num terminal, ou adicione --yes para aceitar todas as recomendações." ;;
    tty_eof) echo "Sem resposta (fim da entrada). Parei; nada mais foi mudado." ;;
    bad_flag) echo "Opção desconhecida: {1}. Veja --help." ;;
    bad_lang) echo "--lang deve ser en ou pt, não {1}." ;;
    bad_version) echo "--version deve ser uma tag como v7.9.2, ou main — não {1}." ;;
    need_value) echo "{1} precisa de um valor. Veja --help." ;;
    bad_profile) echo "--profile {1} não é uma pasta de perfil do Claude Code (precisa existir, e não ser um clone nem um backup)." ;;
    clone_not_git) echo "{1} existe mas não é um clone git. Mova-o, ou aponte HEFESTO_CLONE_DIR para outro lugar." ;;
    clone_remote) echo "{1} é um clone de {2}, não do hefesto. Não vou mexer nele." ;;
    clone_dirty) echo "{1} tem mudanças locais. Paro aqui e não mexo nele. Veja com:  git -C {1} status" ;;
    main_diverged) echo "{1}: a sua main tem commits que não estão na origin/main. Resolva à mão (git -C {1} log origin/main..main) e rode de novo." ;;
    no_remote) echo "Não consigo acessar {1}. Confira a sua rede e rode de novo." ;;
    no_tags) echo "{1} não tem tags de versão (v*)." ;;
    bad_json) echo "{1} não é um JSON válido. Corrija (ou restaure) antes de instalar; não vou sobrescrevê-lo." ;;
    clone_needed) echo "Sem o clone não há o que instalar. Parei; nada foi mudado." ;;
    no_profiles) echo "Nenhum perfil escolhido, então não há onde instalar." ;;
    step_failed) echo "Este passo falhou:  {1}  — parei aqui. A saída acima diz o motivo." ;;
    not_updated) echo "{1} mostra o hefesto {2} depois do passo, não {3}. Parei." ;;
    usage) printf '%s\n' "Uso: install.sh [opções]" "" \
      "Instala ou atualiza o hefesto: clone, plugin em cada perfil, regras e CLAUDE.md." \
      "Mostra o que encontrou e o plano, e pergunta sobre cada passo (Enter = recomendado)." "" \
      "  --yes             aceita todas as recomendações sem perguntar" \
      "  --dry-run         mostra o plano e os comandos; não muda nada" \
      "  --lang en|pt      idioma (padrão: pelo LANG)" \
      "  --profile <pasta> um perfil onde instalar (pode repetir)" \
      "  --version <v>     uma tag de versão (v7.9.2) ou main" \
      "  --help            esta ajuda" ;;
  esac
}

# LC_ALL > LC_MESSAGES > LANG, the order the C library itself uses for message catalogs.
env_lang() {
  case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in pt*) echo pt ;; *) echo en ;; esac
}

msg() { # $1 key, then the values for {1} {2} … → the text, no newline
  local k="$1" t a i=1
  shift
  t="$(msg_"${LNG:-$(env_lang)}" "$k")"
  [ -n "$t" ] || t="$(msg_en "$k")"
  [ -n "$t" ] || t="$k"
  for a in "$@"; do t="$(fill "$t" "{$i}" "$a")"; i=$((i + 1)); done
  printf '%s' "$t"
}

# Splice, not ${t//pat/"$a"}: before bash 4.3 the quotes in that replacement stay in the output
# (macOS /bin/bash 3.2 printed "~/.claude" with its quotes), and without them bash 5.2's
# patsub_replacement turns an & in a path into the matched text.
fill() { # $1 text, $2 placeholder, $3 value → every placeholder replaced by the value
  local t="$1" out=""
  while case "$t" in *"$2"*) true ;; *) false ;; esac; do
    out="$out${t%%"$2"*}$3"
    t="${t#*"$2"}"
  done
  printf '%s' "$out$t"
}
say() { printf '%s\n' "$(msg "$@")"; }
# A first clone that dies half-way leaves its .partial folder: the wizard never deletes, so it
# names the folder instead (a trap that rm -rf's a computed path is the riskier trade).
die() {
  printf '\n%s\n' "$(msg "$@")" >&2
  if [ -n "$PARTIAL" ] && [ -e "$PARTIAL" ]; then printf '%s\n' "$(msg partial_left "$PARTIAL")" >&2; fi
  exit 1
}

tilde() { # display a path with ~ for $HOME — display only, commands always get the full path
  case "$1" in "$HOME") printf '\176' ;; "$HOME"/*) printf '\176/%s' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac
}

# --- Questions -----------------------------------------------------------------------------------
# The tty is opened ONCE as fd 3 (answers) and fd 4 (prompts). stdin is never read: under
# `bash <(curl …)` it is the user's terminal, but under a pipe it would be the script itself.
open_tty() {
  if [ "$YES" = 1 ] || [ "$DRY" = 1 ]; then return 0; fi
  local src="${HEFESTO_TTY:-/dev/tty}" out="${HEFESTO_TTY_OUT:-/dev/tty}"
  { : <"$src"; } 2>/dev/null || die no_tty
  exec 3<"$src"
  if { : >>"$out"; } 2>/dev/null; then exec 4>>"$out"; else exec 4>&2; fi
}

ask() { # $1 key, $2 default y|n, then the key's values → 0 yes, 1 no
  local key="$1" d="$2" a hint
  shift 2
  if [ "$YES" = 1 ] || [ "$DRY" = 1 ]; then [ "$d" = y ]; return; fi
  if [ "$d" = y ]; then hint="$(msg hint_yes)"; else hint="$(msg hint_no)"; fi
  while :; do
    printf '%s %s ' "$(msg "$key" "$@")" "$hint" >&4
    IFS= read -r a <&3 || die tty_eof
    a="$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')"
    case "${a:-$d}" in
      y|yes|s|sim) return 0 ;;
      n|no|nao|não|nÃo) return 1 ;;
    esac
    printf '%s\n' "$(msg ans_again)" >&4
  done
}

# --- Changes -------------------------------------------------------------------------------------
# EVERY change goes through run: it prints the command, and under --dry-run that is all it does.
# That keeps the dry run honest by construction (and tests/smoke.sh mutation-tests it).
quote_cmd() { local out="" a; for a in "$@"; do out="$out $(printf '%q' "$a")"; done; printf '%s' "${out# }"; }

run() {
  printf '  $ %s\n' "$(quote_cmd "$@")"
  [ "$DRY" = 1 ] && return 0
  "$@" </dev/null || die step_failed "$(quote_cmd "$@")"
}

# Each profile gets its own CLAUDE_CONFIG_DIR, set explicitly, so a value exported in the caller's
# shell can never send a profile's install somewhere else. The default profile UNSETS it: with the
# variable set, Claude Code keeps .claude.json inside the folder instead of at ~/.claude.json.
run_claude() { # $1 profile, then the claude arguments
  local p="$1"
  shift
  if [ "$p" = "$HOME/.claude" ]; then
    run $TIMEOUT env -u CLAUDE_CONFIG_DIR claude "$@"
  else
    run $TIMEOUT env CLAUDE_CONFIG_DIR="$p" claude "$@"
  fi
}

backup_file() { # $1 profile, $2 path inside it → copied (links dereferenced) under $BK/<profile>/
  local src="$1/$2" dst
  dst="$BK/$(basename "$1")/$2"
  [ -e "$src" ] || return 0
  case "$BACKED" in *"|$dst|"*) return 0 ;; esac
  case "$BACKED" in *"|$(dirname "$dst")/|"*) ;; *) run mkdir -p "$(dirname "$dst")" ;; esac
  BACKED="$BACKED|$dst|$(dirname "$dst")/|"
  run cp -L "$src" "$dst"
}

probe_write() { local f; f="$(mktemp "$1/.hefesto-probe.XXXXXX" 2>/dev/null)" || return 1; rm -f "$f"; }

# --- Arguments and pre-flight --------------------------------------------------------------------
need_value() { [ -n "$2" ] || die need_value "$1"; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) YES=1 ;;
      --dry-run) DRY=1 ;;
      --lang) need_value "$1" "${2:-}"; set_lang "$2"; shift ;;
      --profile) need_value "$1" "${2:-}"; PROFILE_ARGS="$PROFILE_ARGS$(abs_dir "$2")
"; shift ;;
      --version) need_value "$1" "${2:-}"; VERSION_ARG="$2"; shift ;;
      -h|--help) say usage; exit 0 ;;
      *) die bad_flag "$1" ;;
    esac
    shift
  done
  [ -n "$LNG" ] || LNG="$(env_lang)"
  case "$VERSION_ARG" in "") ;; main|v[0-9]*) ;; [0-9]*) VERSION_ARG="v$VERSION_ARG" ;; *) die bad_version "$VERSION_ARG" ;; esac
}

set_lang() { # validated where it is read, so --help or an error after it never calls a missing table
  case "$1" in en|pt) LNG="$1" ;; pt-BR|pt_BR) LNG=pt ;; *) LNG=en; die bad_lang "$1" ;; esac
}

abs_dir() { local d="${1%/}"; case "$d" in /*) printf '%s' "$d" ;; *) printf '%s/%s' "$PWD" "$d" ;; esac; }

tool_hint() { # $1 missing tool → a hint for this OS (the person runs it; the wizard never sudoes)
  if [ "$1" = claude ]; then
    say hint_claude
    [ -x "$HOME/.local/bin/claude" ] && say hint_claude_local "$HOME/.local/bin"
    say hint_alias
  elif [ "$(uname -s)" = Darwin ]; then say hint_mac "$1"
  else say hint_linux "$1"; fi
}

preflight() {
  [ "${HEFESTO_UID:-$(id -u)}" != 0 ] || die root
  [ -z "${CLAUDECODE:-}" ] || die in_claude
  local t missing=0
  for t in git jq claude; do
    command -v "$t" >/dev/null 2>&1 || { tool_hint "$t" >&2; missing=1; }
  done
  [ "$missing" = 0 ] || die missing_tools
  command -v gh >/dev/null 2>&1 || say gh_missing
  [ "$DRY" = 1 ] || probe_write "$HOME" || die home_ro "$HOME"
  # --foreground: a plain timeout runs claude in a background process group, and the CLI touches the
  # terminal (its output is the tty), so the kernel STOPS it (SIGTTOU) — a hang no timeout or Ctrl+C
  # ends, seen on a real upgrade right after "Successfully updated marketplace". -k 10: if the CLI
  # ignores the TERM, it is killed 10 s later.
  if command -v timeout >/dev/null 2>&1; then TIMEOUT="timeout --foreground -k 10 300"
  elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT="gtimeout --foreground -k 10 300"; fi
}

# --- Detection -----------------------------------------------------------------------------------
# A profile (plan change 1): ~/.claude always; another ~/.claude-* needs settings.json or plugins/
# AND .claude.json or projects/ — a third-party tool that only keeps plugins/ is not a profile —
# and is never a backup (*.backup-*) nor the hefesto clone (it holds .claude-plugin/plugin.json).
is_profile() {
  local d="$1"
  [ "$d" = "$HOME/.claude" ] && return 0
  case "$d" in *.backup-*) return 1 ;; esac
  [ -f "$d/.claude-plugin/plugin.json" ] && return 1
  { [ -f "$d/settings.json" ] || [ -d "$d/plugins" ]; } || return 1
  [ -f "$d/.claude.json" ] || [ -d "$d/projects" ]
}

detect_profiles() {
  local d
  printf '%s\n' "$HOME/.claude"
  for d in "$HOME"/.claude-*; do
    [ -d "$d" ] && is_profile "$d" && printf '%s\n' "$d"
  done
}

json_ok() { [ ! -e "$1" ] || jq empty "$1" >/dev/null 2>&1; }

# Constitution 5: an unreadable registry is an error, never "not installed". Only a MISSING file
# means "not installed". Checked over the CHOSEN profiles before any change, outside any $(…), so
# the die really stops the wizard; the reads below stay quiet so detection can still print.
check_json() { # $1 profile
  local f
  for f in settings.json plugins/installed_plugins.json plugins/known_marketplaces.json; do
    json_ok "$1/$f" || die bad_json "$1/$f"
  done
}

reg_field() { # $1 profile, $2 plugin id, $3 field → the user-scope entry's value, or nothing
  local f="$1/plugins/installed_plugins.json"
  [ -f "$f" ] || return 0
  jq -r --arg id "$2" --arg k "$3" \
    '(.plugins[$id] // []) | map(select(.scope == "user")) | (.[0][$k] // empty) | tostring' "$f" 2>/dev/null
}

km_location() { # $1 profile, $2 marketplace name → its folder, or nothing
  local f="$1/plugins/known_marketplaces.json"
  [ -f "$f" ] || return 0
  jq -r --arg n "$2" '.[$n].installLocation // .[$n].source.path // empty' "$f" 2>/dev/null
}

km_source() { # $1 profile → the hefesto marketplace's source type (directory, github, …), or nothing
  local f="$1/plugins/known_marketplaces.json"
  [ -f "$f" ] || return 0
  jq -r '.hefesto.source.source // empty' "$f" 2>/dev/null
}

enabled_in() { # $1 profile → true|false: enabledPlugins in that profile's settings.json
  [ -f "$1/settings.json" ] || { echo false; return; }
  jq -r --arg id "$ID" '.enabledPlugins[$id] == true' "$1/settings.json"
}

validate_profile_args() {
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    { [ -d "$p" ] && [ ! -f "$p/.claude-plugin/plugin.json" ]; } || die bad_profile "$p"
    case "$p" in *.backup-*) die bad_profile "$p" ;; esac
  done <<<"$PROFILE_ARGS"
}

# Under --yes only ~/.claude plus the explicit --profile values: a non-interactive run never
# guesses at folders. Interactively every detected profile is offered, and each one is asked.
pick_candidates() {
  FOUND="$(detect_profiles)"
  validate_profile_args
  if [ -n "$PROFILE_ARGS" ] || [ "$YES" = 1 ]; then
    CANDIDATES="$(printf '%s\n%s' "$HOME/.claude" "$PROFILE_ARGS" | awk 'NF && !seen[$0]++')"
  else
    CANDIDATES="$FOUND"
  fi
}

# An existing clone is reused wherever it is (the marketplace records it), never duplicated.
find_clone() {
  local p loc
  if [ -n "${HEFESTO_CLONE_DIR:-}" ]; then CLONE="$HEFESTO_CLONE_DIR"; return; fi
  CLONE="$HOME/.claude-framework"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    loc="$(km_location "$p" hefesto)"
    [ -n "$loc" ] || continue
    # Only a DIRECTORY marketplace's folder is a clone; a github one's is Claude Code's own cache.
    if [ "$(km_source "$p")" != directory ]; then say mkt_not_dir "$(tilde "$p")" "$(km_source "$p")"; continue; fi
    if [ -d "$loc" ]; then CLONE="$loc"; return; fi
  done <<<"$CANDIDATES"
}

# Profiles whose hefesto marketplace points somewhere other than the clone never converge: each
# `marketplace update` re-reads its own folder. They are re-pointed (S3), after a backup.
find_repoint() {
  local p loc
  REPOINT=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    loc="$(km_location "$p" hefesto)"
    [ -n "$loc" ] || continue
    same_dir "$loc" "$CLONE" || [ "$loc" = "$CLONE" ] || REPOINT="$REPOINT$p
"
  done <<<"$CANDIDATES"
}

norm_url() { # ssh/https/.git spellings of one repository → one string
  printf '%s' "$1" | sed -E 's#^(https?|ssh|git)://##; s#^[^@/]+@##; s#:([^/0-9])#/\1#; s#\.git/?$##; s#/+$##'
}

remote_ok() { # $1 origin URL → 0 when it is hefesto (or its old name, or the HEFESTO_REPO_URL seam)
  local u
  u="$(norm_url "$1")"
  case "$u" in github.com/joaoariedi/hefesto|github.com/joaoariedi/ai-development-framework) return 0 ;; esac
  [ -n "$u" ] && [ "$u" = "$(norm_url "$REPO_URL")" ]
}

clone_dirty() { [ -n "$(git -C "$CLONE" status --porcelain --untracked-files=no 2>/dev/null)" ]; }

inspect_clone() {
  if [ ! -e "$CLONE" ]; then CLONE_STATE=absent; return; fi
  { [ -e "$CLONE/.git" ] && git -C "$CLONE" rev-parse HEAD >/dev/null 2>&1; } || die clone_not_git "$CLONE"
  local url
  url="$(git -C "$CLONE" remote get-url origin 2>/dev/null)"
  remote_ok "$url" || die clone_remote "$CLONE" "${url:-?}"
  # Stop BEFORE any change: a junior's uncommitted edit is exactly what a checkout would destroy.
  clone_dirty && die clone_dirty "$CLONE"
  check_orphan
  CLONE_STATE=present
  CLONE_VER="$(jq -r '.version // empty' "$CLONE/.claude-plugin/plugin.json" 2>/dev/null)"
  CLONE_BRANCH="$(git -C "$CLONE" symbolic-ref -q --short HEAD 2>/dev/null)"
}

# A commit made on a detached HEAD lives on no branch: the next checkout would orphan it (B3).
check_orphan() {
  local c
  c="$(git -C "$CLONE" rev-list -1 HEAD --not --branches --remotes --tags 2>/dev/null)"
  [ -z "$c" ] || die orphan_commit "$CLONE" "$(git -C "$CLONE" rev-parse --short "$c")"
}

clone_where() { # where HEAD is: the branch, the exact tag, or the short commit
  [ -n "$CLONE_BRANCH" ] && { printf '%s' "$CLONE_BRANCH"; return; }
  git -C "$CLONE" describe --tags --exact-match HEAD 2>/dev/null || git -C "$CLONE" rev-parse --short HEAD
}

ver_gt() { # $1 > $2, dotted numeric versions (sort -V is not on every macOS)
  local a b i
  IFS=. read -r -a a <<<"$1"
  IFS=. read -r -a b <<<"$2"
  for i in 0 1 2; do
    [ "${a[$i]:-0}" -gt "${b[$i]:-0}" ] 2>/dev/null && return 0
    [ "${a[$i]:-0}" -lt "${b[$i]:-0}" ] 2>/dev/null && return 1
  done
  return 1
}

find_latest() {
  local refs t best=""
  refs="$(git ls-remote --tags --refs "$REPO_URL" 'v*' 2>/dev/null)" || die no_remote "$REPO_URL"
  for t in $(printf '%s\n' "$refs" | sed -n 's#.*refs/tags/\(v[0-9][0-9.]*\)$#\1#p'); do
    if [ -z "$best" ] || ver_gt "${t#v}" "${best#v}"; then best="$t"; fi
  done
  [ -n "$best" ] || die no_tags "$REPO_URL"
  LATEST="$best"
  TAGS="$(printf '%s\n' "$refs" | sed -n 's#.*refs/tags/\(v[0-9][0-9.]*\)$#\1#p' | tr '\n' ' ')"
  # An explicit --version is checked against the remote before ANY change (B2): a typo must not
  # get as far as a half-made clone.
  case "$VERSION_ARG" in ""|main) ;; *) case " $TAGS" in *" $VERSION_ARG "*) ;; *) die no_such_tag "$VERSION_ARG" "${TAGS% }" ;; esac ;; esac
}

# A clone on main at or ahead of the latest release stays on main: recommending the tag would
# quietly downgrade someone who follows main. Everyone else gets the latest release.
recommend_version() {
  if [ -n "$VERSION_ARG" ]; then TARGET="$VERSION_ARG"; return; fi
  if [ "$CLONE_STATE" = present ] && [ "$CLONE_BRANCH" = main ] && [ -n "$CLONE_VER" ] \
     && ! ver_gt "${LATEST#v}" "$CLONE_VER"; then
    TARGET=main; REC_MAIN=1
  else
    TARGET="$LATEST"
  fi
}

# Old-install files (B1). With a clone, a file is hefesto's only when its bytes match a blob that
# the clone's history shipped at that path: a person's own code-reviewer.md is not legacy. With no
# clone yet (a fresh machine) there is nothing to compare with, so the known names are "possibly".
load_legacy_blobs() {
  [ "$CLONE_STATE" = present ] || return 0
  LEGACY_BLOBS="$(git -C "$CLONE" log --all --format= --raw --no-abbrev -- commands agents hooks \
    .claude/commands .claude/agents .claude/hooks 2>/dev/null | awk '{print $4, $NF}')"
}

shipped_blob() { # $1 file, $2 its path below the profile (agents/x.md) → 0 when history shipped it
  local h
  h="$(git hash-object "$1" 2>/dev/null)" || return 1
  awk -v h="$h" -v t="$2" '$1 == h && ($2 == t || substr($2, length($2) - length(t)) == "/" t) { f = 1 }
    END { exit !f }' <<<"$LEGACY_BLOBS"
}

legacy_files() { # $1 profile → "old<TAB>path" (matches hefesto's history) or "maybe<TAB>path"
  local p="$1" f n
  if [ "$CLONE_STATE" = present ]; then
    for f in "$p"/commands/* "$p"/agents/* "$p"/hooks/*; do
      [ -f "$f" ] && shipped_blob "$f" "$(basename "$(dirname "$f")")/$(basename "$f")" && printf 'old\t%s\n' "$f"
    done
    return 0
  fi
  for f in "$p"/commands/speckit.*.md "$p"/commands/hef.*.md "$p"/hooks/speckit-helper.sh; do
    if path_exists "$f"; then printf 'maybe\t%s\n' "$f"; fi
  done
  for n in code-reviewer forensic-specialist quality-guardian repo-scout review-coordinator test-specialist truth-scout; do
    f="$p/agents/$n.md"
    if path_exists "$f"; then printf 'maybe\t%s\n' "$f"; fi
  done
}

# How to undo the stow that linked a flagged file (S7): the package is wherever the link points,
# minus the file's path below $HOME — never a guessed ~/dotfiles + claude.
stow_hint() { # $1 flagged file
  local x t rel pkg
  for x in "$1" "$(dirname "$1")"; do
    [ -L "$x" ] || continue
    t="$(readlink "$x")"
    case "$t" in /*) ;; *) t="$(cd "$(dirname "$x")" 2>/dev/null && cd "$(dirname "$t")" 2>/dev/null && pwd)/$(basename "$t")" ;; esac
    rel="${x#"$HOME"/}"
    case "$t" in */"$rel") pkg="${t%/"$rel"}"; say legacy_stow "$(tilde "$(dirname "$pkg")")" "$(basename "$pkg")"; return ;; esac
    say legacy_unstow "$(tilde "$x")"
    return
  done
}

detect() {
  pick_candidates
  find_clone
  inspect_clone
  find_latest
  recommend_version
  find_repoint
  load_legacy_blobs
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -n "$(reg_field "$p" "$OLD_ID" version)" ] && OLD_IN="$OLD_IN$p
"
  done <<<"$CANDIDATES"
}

# --- What I found, and the plan --------------------------------------------------------------------
print_profiles() {
  local p v
  say f_profiles
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    v="$(reg_field "$p" "$ID" version)"
    if [ -n "$v" ]; then printf '    %-28s %s\n' "$(tilde "$p")" "$(msg f_prof_ver "$v")"
    else printf '    %-28s %s\n' "$(tilde "$p")" "$(msg f_prof_none)"; fi
  done <<<"$CANDIDATES"
  while IFS= read -r p; do
    [ -n "$p" ] && say f_prof_other "$(tilde "$p")" "$(tilde "$(km_location "$p" hefesto)")"
  done <<<"$REPOINT"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "
$CANDIDATES
" in *"
$p
"*) ;; *) say f_prof_unchosen "$(tilde "$p")" ;; esac
  done <<<"$FOUND"
}

print_old() {
  local p f any=0
  while IFS= read -r p; do [ -n "$p" ] && { say f_old_plugin "$(tilde "$p")"; any=1; }; done <<<"$OLD_IN"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      any=1
      if [ "${f%%	*}" = maybe ]; then say f_legacy_maybe "$(tilde "${f#*	}")"
      elif [ -L "${f#*	}" ]; then say f_legacy_link "$(tilde "${f#*	}")" "$(readlink "${f#*	}")"
      else say f_legacy_file "$(tilde "${f#*	}")"; fi
    done <<<"$(legacy_files "$p")"
  done <<<"$CANDIDATES"
  [ "$any" = 1 ] || say f_old_none
}

print_findings() {
  echo
  say found_header
  if [ "$CLONE_STATE" = absent ]; then say f_clone_absent "$(tilde "$CLONE")"
  else say f_clone "$(tilde "$CLONE")" "${CLONE_VER:-?}" "$(clone_where)" "$(msg f_dirty_no)"; fi
  say f_latest "$LATEST"
  print_profiles
  print_old
}

build_steps() {
  STEPS="backup"
  [ -n "$OLD_IN" ] && STEPS="$STEPS oldplugin"
  [ -z "$VERSION_ARG" ] && STEPS="$STEPS version"
  STEPS="$STEPS clone"
  [ -n "$REPOINT" ] && STEPS="$STEPS repoint"
  STEPS="$STEPS profiles rules claudemd"
}

step_text() { # $1 step → its one-line description
  case "$1" in
    backup) msg st_backup "$(tilde "$BK")/" ;;
    oldplugin) msg st_oldplugin ;;
    version) if [ "$REC_MAIN" = 1 ]; then msg st_stay_main "$LATEST"; else msg st_use_tag "$LATEST"; fi ;;
    clone) if [ "$CLONE_STATE" = absent ]; then msg st_clone "$(tilde "$CLONE")"; else msg st_update "$(tilde "$CLONE")"; fi ;;
    repoint) msg st_repoint "$(printf '%s\n' "$REPOINT" | awk 'NF' | wc -l | tr -d ' ')" "$(tilde "$CLONE")" ;;
    profiles) msg st_profiles "$(printf '%s\n' "$CANDIDATES" | awk 'NF' | wc -l | tr -d ' ')" ;;
    rules) msg st_rules ;;
    claudemd) msg st_claudemd ;;
  esac
}

step_why() { # $1 step → why it is recommended
  case "$1" in
    version) if [ "$REC_MAIN" = 1 ]; then msg why_main; else msg why_tag; fi ;;
    clone) if [ "$CLONE_STATE" = absent ]; then msg why_clone; else msg why_update; fi ;;
    *) msg "why_$1" ;;
  esac
}

print_plan() {
  local k n=0
  build_steps
  echo
  say plan_header "$(echo $STEPS | wc -w | tr -d ' ')"
  for k in $STEPS; do
    n=$((n + 1))
    printf '  %s. %s\n' "$n" "$(step_text "$k")"
    say why "$(step_why "$k")"
  done
  echo
}

# --- Answers ---------------------------------------------------------------------------------------
choose_profiles() { # $1 step number
  local p
  CHOSEN=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if ask q_profile y "$1" "$(tilde "$p")"; then CHOSEN="$CHOSEN$p
"; else say skipped_profile "$(tilde "$p")"; fi
  done <<<"$CANDIDATES"
}

set_answer() { # $1 step, $2 1|0
  case "$1" in
    backup) DO_BACKUP="$2" ;;
    oldplugin) DO_OLD="$2" ;;
    clone) DO_CLONE="$2" ;;
    rules) DO_RULES="$2" ;;
    claudemd) DO_CMD="$2" ;;
    repoint) DO_REPOINT="$2" ;;
    version) [ "$2" = 1 ] || { if [ "$REC_MAIN" = 1 ]; then TARGET="$LATEST"; else TARGET=main; fi; } ;;
  esac
}

ask_steps() {
  local k n=0
  if [ "$DRY" = 1 ]; then say dry_auto; elif [ "$YES" = 1 ]; then say auto_yes; fi
  for k in $STEPS; do
    n=$((n + 1))
    if [ "$k" = profiles ]; then choose_profiles "$n"; continue; fi
    if ask q_step y "$n" "$(step_text "$k")"; then set_answer "$k" 1; else set_answer "$k" 0; say skipped "$n"; fi
  done
}

# The old install's files are only REPORTED (plan simplification a): they may be links into
# someone's dotfiles, so the person moves them. The default answer is to stop before installing.
# Each file gets its own folder per profile and kind (B1): two profiles both holding
# agents/code-reviewer.md must not paste into one destination and lose a file.
gate_legacy() {
  local p line f d dirs="" any=0 hints=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      [ "$any" = 1 ] || { echo; say legacy_cmds; any=1; }
      f="${line#*	}"; d="$BK/legacy/$(basename "$p")/$(basename "$(dirname "$f")")"
      case "$dirs" in *"|$d|"*) ;; *) printf '  $ mkdir -p %q\n' "$d"; dirs="$dirs|$d|" ;; esac
      printf '  $ mv %q %q\n' "$f" "$d/"
      hints="$hints$(stow_hint "$f")
"
    done <<<"$(legacy_files "$p")"
  done <<<"$CHOSEN"
  [ "$any" = 1 ] || return 0
  printf '%s' "$hints" | awk 'NF && !seen[$0]++'
  ask q_legacy n || die legacy_stop
}

check_answers() {
  [ "$DO_CLONE" = 1 ] || [ "$CLONE_STATE" = present ] || die clone_needed
  [ -n "$CHOSEN" ] || die no_profiles
  each_profile check_json
  gate_legacy
  [ "$DRY" = 1 ] && return 0
  local p
  while IFS= read -r p; do
    [ -n "$p" ] && [ -d "$p" ] && { probe_write "$p" || die not_writable "$p"; }
  done <<<"$CHOSEN"
}

# --- Execution -------------------------------------------------------------------------------------
each_profile() { # $1 function → called once per chosen profile (not in a subshell, so die stops)
  local p
  while IFS= read -r p; do [ -n "$p" ] && "$1" "$p"; done <<<"$CHOSEN"
}

backup_profile() {
  local f
  for f in settings.json CLAUDE.md plugins/installed_plugins.json plugins/known_marketplaces.json; do
    backup_file "$1" "$f"
  done
}

same_dir() { [ -d "$1" ] && [ -d "$2" ] && [ "$(cd "$1" && pwd -P)" = "$(cd "$2" && pwd -P)" ]; }

remove_old_plugin() {
  local p="$1" loc
  [ -n "$(reg_field "$p" "$OLD_ID" version)" ] || return 0
  # Backed up here even when the backup step was declined: the re-point step backs up the same
  # file later, and by then this removal would already have changed it.
  backup_file "$p" plugins/known_marketplaces.json
  backup_file "$p" plugins/installed_plugins.json
  run_claude "$p" plugin uninstall "$OLD_ID" --scope user
  loc="$(km_location "$p" ai-development-framework)"
  [ -n "$loc" ] || return 0
  if same_dir "$loc" "$CLONE"; then say keep_old_mkt "$p"; return 0; fi
  run_claude "$p" plugin marketplace remove ai-development-framework --scope user
}

sync_main() {
  if [ -z "$(git -C "$CLONE" rev-parse --abbrev-ref 'main@{upstream}' 2>/dev/null)" ]; then
    if git -C "$CLONE" rev-parse -q --verify refs/heads/main >/dev/null \
       && ! git -C "$CLONE" merge-base --is-ancestor main origin/main; then die main_diverged "$CLONE"; fi
    run git -C "$CLONE" checkout -q -B main origin/main
    return
  fi
  git -C "$CLONE" merge-base --is-ancestor main origin/main || die main_diverged "$CLONE"
  run git -C "$CLONE" checkout -q main
  run git -C "$CLONE" merge -q --ff-only origin/main
}

sync_clone() {
  if [ "$CLONE_STATE" = absent ]; then
    # Not `clone --branch <tag>`: git 2.56 warns "refs/tags/… is not a commit!" for an annotated
    # tag, which reads like an error to the person watching. Clone, then check the tag out.
    # Into a folder beside the target, renamed only once the checkout succeeded (B2): a failed
    # first clone must leave no half-made ~/.claude-framework that the next run would refuse.
    local tmp="$CLONE.partial-$$"
    say clone_tmp "$(tilde "$tmp")"
    PARTIAL="$tmp"
    if [ "$TARGET" = main ]; then run git clone -q --branch main "$REPO_URL" "$tmp"
    else
      run git clone -q --no-checkout "$REPO_URL" "$tmp"
      run git -C "$tmp" -c advice.detachedHead=false checkout -q "$TARGET"
    fi
    run mv "$tmp" "$CLONE"
    PARTIAL=""
    return
  fi
  clone_dirty && die clone_dirty "$CLONE"   # again: nothing may have changed it since detection
  check_orphan
  run git -C "$CLONE" fetch -q --tags origin
  if [ "$TARGET" = main ]; then sync_main
  else run git -C "$CLONE" -c advice.detachedHead=false checkout -q "$TARGET"; fi
}

repoint_profile() { # $1 profile → its hefesto marketplace re-pointed at the chosen clone (S3)
  case "
$REPOINT" in *"
$1
"*) ;; *) return 0 ;; esac
  backup_file "$1" plugins/known_marketplaces.json
  run_claude "$1" plugin marketplace remove hefesto --scope user
  run_claude "$1" plugin marketplace add "$CLONE" --scope user
}

target_version() { # the version the profiles must end at
  if [ -f "$CLONE/.claude-plugin/plugin.json" ] && [ "$DRY" = 0 ]; then
    jq -r '.version' "$CLONE/.claude-plugin/plugin.json"
  elif [ "$CLONE_STATE" = present ] && [ "$TARGET" = main ]; then printf '%s' "$CLONE_VER"
  else printf '%s' "${TARGET#v}"; fi
}

check_installed() { # $1 profile — the outcome is read from the registry, never parsed from output
  local v
  v="$(reg_field "$1" "$ID" version)"
  [ "$v" = "$(target_version)" ] || die not_updated "$1" "${v:--}" "$(target_version)"
}

install_plugin() {
  local p="$1" have want
  want="$(target_version)"
  if [ -n "$(km_location "$p" hefesto)" ]; then run_claude "$p" plugin marketplace update hefesto
  else run_claude "$p" plugin marketplace add "$CLONE" --scope user; fi
  have="$(reg_field "$p" "$ID" version)"
  if [ -z "$have" ]; then run_claude "$p" plugin install "$ID" --scope user
  elif [ "$have" != "$want" ]; then run_claude "$p" plugin update "$ID" --scope user
  elif [ -d "$CLONE/.git" ] && [ "$(reg_field "$p" "$ID" gitCommitSha)" != "$(git -C "$CLONE" rev-parse HEAD)" ]; then
    say reinstall_same "$have"   # `plugin update` compares versions only (docs/install.md §5)
    run_claude "$p" plugin uninstall "$ID" --scope user
    run_claude "$p" plugin install "$ID" --scope user
  else
    say already_current "$(tilde "$p")" "$have"
  fi
  [ "$DRY" = 1 ] || check_installed "$p"
}

copy_rules() {
  local p="$1" src f dst
  if [ -L "$p/rules" ]; then say rules_link "$(tilde "$p/rules")"; return 0; fi
  if [ ! -d "$CLONE/.claude/rules" ]; then say dry_later; return 0; fi
  [ -d "$p/rules" ] || run mkdir -p "$p/rules"
  for src in "$CLONE"/.claude/rules/*.md; do
    f="$(basename "$src")"; dst="$p/rules/$f"
    if [ -L "$dst" ]; then say file_link_skip "$(tilde "$dst")"; continue; fi
    if [ -e "$dst" ]; then
      cmp -s "$src" "$dst" && continue
      backup_file "$p" "rules/$f"
    fi
    run cp "$src" "$dst"
  done
}

write_claude_md() { # $1 source, $2 destination, $3 1 = end with the import of the person's own file
  [ "$3" = 1 ] || { run cp "$1" "$2"; return; }
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/hefesto-claude.XXXXXX")" || die step_failed "mktemp"
  { cat "$1"; printf '\n@CLAUDE.md.mine\n'; } >"$tmp"
  run cp "$tmp" "$2"
  rm -f "$tmp"
}

path_exists() { [ -e "$1" ] || [ -L "$1" ]; }   # true for a dangling link too

# CLAUDE.md (user decision 2026-10-13, "Hefesto + import theirs"): absent → hefesto's; a previous
# hefesto copy → replaced (keeping the import when a .mine exists); anything else → MOVED to
# CLAUDE.md.mine (a link moves as a link, never written through) and imported from hefesto's.
# The CLAUDE.md the clone's history shipped, by blob hash. A file that merely STARTS with
# "# Hefesto v" may carry the person's own additions (review 2026-10-13): only a byte-identical
# shipped copy — or one plus the import line this wizard appends — counts as "previous hefesto".
is_hefesto_copy() { # $1 file
  [ -d "$CLONE/.git" ] || return 1
  [ -n "$CMD_BLOBS" ] || CMD_BLOBS="$(git -C "$CLONE" log --all --format= --raw --no-abbrev -- .claude/CLAUDE.md | awk '{print $4}')"
  grep -qx "$(git hash-object "$1")" <<<"$CMD_BLOBS" && return 0
  [ "$(tail -n 1 "$1")" = "@CLAUDE.md.mine" ] || return 1
  grep -qx "$(sed '$d' "$1" | sed '$d' | git hash-object --stdin)" <<<"$CMD_BLOBS"
}

# CLAUDE.md (user decision 2026-10-13, "Hefesto + import theirs"): absent → hefesto's (importing an
# existing .mine); a shipped hefesto copy → replaced, keeping the import; anything else → MOVED to
# CLAUDE.md.mine (a link moves as a link, never written through) and imported from hefesto's.
copy_claude_md() {
  local p="$1" src="$CLONE/.claude/CLAUDE.md" dst="$1/CLAUDE.md" mine="$1/CLAUDE.md.mine" mi=0
  [ -f "$src" ] || { say dry_later; return 0; }
  path_exists "$mine" && mi=1
  if ! path_exists "$dst"; then write_claude_md "$src" "$dst" "$mi"; return 0; fi
  if [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then say cmd_current "$(tilde "$dst")"; return 0; fi
  if [ ! -L "$dst" ] && is_hefesto_copy "$dst"; then
    backup_file "$p" CLAUDE.md; write_claude_md "$src" "$dst" "$mi"; return 0
  fi
  if [ "$mi" = 1 ]; then say mine_exists "$(tilde "$mine")" "$(tilde "$dst")"; return 0; fi
  backup_file "$p" CLAUDE.md
  run mv "$dst" "$mine"
  write_claude_md "$src" "$dst" 1
}

# The clone first (S5): the old plugin's marketplace is compared with it, and every later step
# reads from it.
execute() {
  say run_header
  [ "$DO_BACKUP" = 1 ] && each_profile backup_profile
  [ "$DO_CLONE" = 1 ] && sync_clone
  [ "$DO_OLD" = 1 ] && each_profile remove_old_plugin
  [ "$DO_REPOINT" = 1 ] && each_profile repoint_profile
  if [ "$DRY" = 1 ] && [ "$CLONE_STATE" = present ] && [ "$DO_CLONE" = 1 ]; then say dry_checkout_note; fi
  each_profile install_plugin
  [ "$DO_RULES" = 1 ] && each_profile copy_rules
  [ "$DO_CMD" = 1 ] && each_profile copy_claude_md
  return 0
}

# --- Verification ------------------------------------------------------------------------------------
verify() {
  local p v e want bad=0
  want="$(target_version)"
  echo; say verify_header
  printf '  %-28s %-10s %s\n' "$(msg col_profile)" "$(msg col_version)" "$(msg col_enabled)"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    v="$(reg_field "$p" "$ID" version)"; e="$(enabled_in "$p")"
    if [ "$e" = true ]; then e="$(msg w_yes)"; else e="$(msg w_no)"; bad=1; fi
    printf '  %-28s %-10s %s\n' "$(tilde "$p")" "${v:--}" "$e"
    [ "$v" = "$want" ] || bad=1
  done <<<"$CHOSEN"
  echo
  if [ "$bad" = 0 ]; then say all_good "$want"; else say verify_failed "$want"; fi
  [ -d "$BK" ] && say backup_note "$(tilde "$BK")"
  echo; say next_header
  say next_restart; say next_line "$want"; say next_doctor
  if [ "${LNG:-en}" = pt ]; then say next_sessions "$QUICKSTART.pt-BR.md"; else say next_sessions "$QUICKSTART.md"; fi
  say next_guide "$GUIDE"
  return "$bad"
}

main() {
  init_globals
  parse_args "$@"
  preflight
  cd "$HOME" || die home_ro "$HOME"   # a project's .claude/ in the cwd must not shadow user scope
  open_tty
  say title
  detect
  print_findings
  print_plan
  ask_steps
  check_answers
  echo
  execute
  if [ "$DRY" = 1 ]; then echo; say dry_done; exit 0; fi
  verify || exit 1
}

main "$@"
