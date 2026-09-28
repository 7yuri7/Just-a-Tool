#!/usr/bin/env bash
#
# dev-tools - Central TUI de Manutenção, Auditoria e Provisionamento Dev
#

# Impede a execução direta como root (preserva permissões de arquivos na /home)
if [ "$EUID" -eq 0 ]; then
  echo "Erro: Não execute este script como root ou com sudo."
  echo "Execute como seu usuário comum; privilégios de sudo serão solicitados pontualmente."
  exit 1
fi

# Exporta caminhos essenciais para o usuário
export PATH="$HOME/.local/bin:$PATH"

# ==============================================================================
# Verificação de Dependências Básicas
# ==============================================================================

if ! command -v dialog &>/dev/null; then
  echo "O utilitário 'dialog' não foi encontrado."
  read -rp "Deseja instalar agora via pacman? [S/n]: " resp
  if [[ "$resp" =~ ^[Ss] || -z "$resp" ]]; then
    sudo pacman -S --needed dialog
  else
    echo "A execução foi abortada por falta da dependência 'dialog'."
    exit 1
  fi
fi

# ==============================================================================
# Variáveis Globais e Configurações
# ==============================================================================

REPO_DIR="$HOME/.local/share/tui-dev-presets"
CONFIG_FILE="$HOME/.config/dev-tools/repo.conf"

# ==============================================================================
# Funções de Medição de Armazenamento
# ==============================================================================

get_available_space_kb() {
  df -k --output=source,avail / "$HOME" 2>/dev/null |
    tail -n +2 |
    sort -u -k1,1 |
    awk '{sum += $2} END {print sum}'
}

format_size() {
  local kb=$1
  awk -v k="$kb" '
    BEGIN {
        if (k >= 1048576) {
            printf "%.2f GB", k / 1048576
        } else if (k >= 1024) {
            printf "%.2f MB", k / 1024
        } else {
            printf "%d KB", k
        }
    }'
}

pause_screen() {
  local space_before=$1
  local space_after
  space_after=$(get_available_space_kb)

  local freed_kb=$((space_after - space_before))

  echo -e "\n========================================================"
  echo "                 RESUMO DA OPERAÇÃO                     "
  echo "========================================================"
  echo "Espaço livre antes : $(format_size "$space_before")"
  echo "Espaço livre atual : $(format_size "$space_after")"

  if [ "$freed_kb" -gt 0 ]; then
    echo -e "Espaço liberado    : \033[1;32m$(format_size "$freed_kb")\033[0m"
  else
    echo "Espaço liberado    : 0 MB (nenhuma variação perceptível)"
  fi
  echo "========================================================"
  echo ""
  read -rp "Pressione [ENTER] para voltar ao menu..."
}

# ==============================================================================
# Funções de Limpeza Geral do Sistema
# ==============================================================================

clean_orphans() {
  echo -e "\n--> Verificando pacotes órfãos..."
  orphans=$(pacman -Qtdq 2>/dev/null || true)
  if [ -n "$orphans" ]; then
    echo "Removendo pacotes órfãos:"
    echo "$orphans"
    sudo pacman -Rns --noconfirm $orphans || true
  else
    echo "Nenhum pacote órfão encontrado."
  fi
}

clean_pacman() {
  echo -e "\n--> Limpando cache do pacman..."
  if command -v paccache &>/dev/null; then
    sudo paccache -r -k 2 || true
    sudo paccache -ruk0 || true
  else
    sudo pacman -Sc --noconfirm || true
  fi
}

clean_aur() {
  echo -e "\n--> Limpando caches de AUR (Paru / Yay)..."
  if command -v paru &>/dev/null; then
    paru -Sc --noconfirm || true
    rm -rf ~/.cache/paru/clone/* 2>/dev/null || true
  fi
  if command -v yay &>/dev/null; then
    yay -Sc --noconfirm || true
    rm -rf ~/.cache/yay/* 2>/dev/null || true
  fi
}

clean_systemd() {
  echo -e "\n--> Otimizando logs do journalctl e coredumps..."
  sudo journalctl --vacuum-time=2weeks || true
  sudo journalctl --vacuum-size=100M || true
  sudo rm -rf /var/lib/systemd/coredump/* 2>/dev/null || true
}

clean_trash() {
  echo -e "\n--> Esvaziando lixeira e miniaturas..."
  rm -rf ~/.local/share/Trash/* 2>/dev/null || true
  rm -rf ~/.cache/thumbnails/* 2>/dev/null || true
  rm -rf ~/.cache/zsh/* ~/.cache/bash/* 2>/dev/null || true
}

clean_flatpak() {
  if command -v flatpak &>/dev/null; then
    echo -e "\n--> Removendo runtimes não utilizados do Flatpak..."
    flatpak uninstall --unused -y || true
  fi
}

# ==============================================================================
# Funções de Limpeza de Ambiente de Desenvolvimento
# ==============================================================================

clean_docker() {
  echo -e "\n--> Limpando ecossistemas de containers..."
  if command -v docker &>/dev/null; then
    if docker info &>/dev/null; then
      echo "Executando docker system prune..."
      docker system prune -f || true
    else
      echo "Docker instalado, mas o daemon não está ativo. Pulando..."
    fi
  fi

  if command -v podman &>/dev/null; then
    echo "Executando podman system prune..."
    podman system prune -f || true
  fi
}

clean_mise() {
  if command -v mise &>/dev/null; then
    echo -e "\n--> Limpando runtimes não utilizadas e cache do Mise..."
    mise prune -y 2>/dev/null && echo "✓ Runtimes órfãs do Mise podadas" || true

    if mise cache clean &>/dev/null; then
      echo "✓ Cache de downloads do Mise limpo"
    else
      rm -rf "$HOME/.cache/mise"/* 2>/dev/null || true
      echo "✓ Diretório ~/.cache/mise limpo"
    fi
  fi
}

clean_dev_caches() {
  echo -e "\n--> Limpando caches de gerenciadores de linguagens..."

  # Node / JS
  if command -v npm &>/dev/null; then
    npm cache clean --force 2>/dev/null && echo "✓ Cache npm limpo" || true
  fi
  if command -v yarn &>/dev/null; then
    yarn cache clean 2>/dev/null && echo "✓ Cache yarn limpo" || true
  fi
  if command -v pnpm &>/dev/null; then
    pnpm store prune 2>/dev/null && echo "✓ Store pnpm podado" || true
  fi

  # Python
  if command -v pip &>/dev/null; then
    pip cache purge 2>/dev/null && echo "✓ Cache pip limpo" || true
  fi

  # Go
  if command -v go &>/dev/null; then
    go clean -cache -modcache -testcache 2>/dev/null && echo "✓ Cache Go limpo" || true
  fi

  # Rust
  if [ -d "$HOME/.cargo/registry/cache" ]; then
    rm -rf "$HOME/.cargo/registry/cache"/* 2>/dev/null || true
    echo "✓ Cache de crates Cargo limpo"
  fi

  # Gradle / Maven
  if [ -d "$HOME/.gradle/caches" ]; then
    rm -rf "$HOME/.gradle/caches"/* 2>/dev/null || true
    echo "✓ Caches Gradle removidos"
  fi
  if [ -d "$HOME/.m2/repository" ]; then
    rm -rf "$HOME/.m2/repository"/* 2>/dev/null || true
    echo "✓ Repositório local Maven limpo"
  fi
}

clean_ide_caches() {
  echo -e "\n--> Limpando caches de IDEs e editores..."

  # VS Code
  if [ -d "$HOME/.config/Code" ]; then
    rm -rf "$HOME/.config/Code/User/workspaceStorage"/* 2>/dev/null || true
    rm -rf "$HOME/.config/Code/CachedData"/* 2>/dev/null || true
    rm -rf "$HOME/.cache/vscode-cpptools"/* 2>/dev/null || true
    echo "✓ Caches e workspaces do VS Code limpos"
  fi

  # VSCodium
  if [ -d "$HOME/.config/VSCodium" ]; then
    rm -rf "$HOME/.config/VSCodium/User/workspaceStorage"/* 2>/dev/null || true
    rm -rf "$HOME/.config/VSCodium/CachedData"/* 2>/dev/null || true
    echo "✓ Caches do VSCodium limpos"
  fi

  # JetBrains
  if [ -d "$HOME/.cache/JetBrains" ]; then
    rm -rf "$HOME/.cache/JetBrains"/* 2>/dev/null || true
    echo "✓ Caches e índices do JetBrains limpos"
  fi
}

# ==============================================================================
# Auditoria e Diagnóstico
# ==============================================================================

inspect_heavy_packages() {
  local tmpfile
  tmpfile=$(mktemp)

  dialog --infobox "Calculando tamanho dos pacotes instalados..." 4 55

  local result
  result=$(LC_ALL=C pacman -Qi | awk '
        /^Name/ { name = $3 }
        /^Installed Size/ {
            val = $4; unit = $5
            if (unit == "KiB") kb = val
            else if (unit == "MiB") kb = val * 1024
            else if (unit == "GiB") kb = val * 1048576
            else kb = val / 1024
        }
        /^Install Reason/ {
            reason = ($4 == "Explicitly" ? "[Manual]" : "[Dep]")
            printf "%10.2f MiB  %-8s  %s\n", kb / 1024, reason, name
        }
    ' | sort -hr | head -n 50)

  {
    echo "TAMANHO       TIPO      PACOTE (TOP 50)"
    echo "------------------------------------------------------------------"
    echo "$result"
    echo "------------------------------------------------------------------"
    echo "[Manual] = Instalado por você | [Dep] = Dependência de outro app"
    echo "Use as setas para rolar. Pressione [ESC] ou [ENTER] para sair."
  } >"$tmpfile"

  dialog \
    --backtitle "Arch Linux - Central de Limpeza e Otimização" \
    --title " Maiores Pacotes em Disco " \
    --textbox "$tmpfile" 22 72

  rm -f "$tmpfile"
}

diagnose_system() {
  local tmpfile
  tmpfile=$(mktemp)

  dialog --infobox "Executando diagnósticos do sistema e hardware..." 4 60

  {
    echo "=================================================================="
    echo "                 RELATÓRIO DE SAÚDE DO SISTEMA                    "
    echo "=================================================================="
    echo "Data: $(date '+%d/%m/%Y %H:%M:%S') | Kernel: $(uname -r)"
    echo ""

    echo "[1] SERVIÇOS SYSTEMD EM FALHA"
    echo "------------------------------------------------------------------"
    local failed_units
    failed_units=$(systemctl --failed --no-legend --plain 2>/dev/null || true)
    if [ -n "$failed_units" ]; then
      echo "$failed_units"
    else
      echo "✓ Nenhum serviço ou daemon com falha detectado."
    fi
    echo ""

    echo "[2] INTEGRIDADE DE DEPENDÊNCIAS DO PACMAN"
    echo "------------------------------------------------------------------"
    local dep_errors
    dep_errors=$(pacman -Dk 2>&1 || true)
    if [ -n "$dep_errors" ]; then
      echo "$dep_errors"
    else
      echo "✓ Todas as dependências do sistema estão satisfeitas."
    fi
    echo ""

    echo "[3] ARQUIVOS DE CONFIGURAÇÃO PENDENTES (.pacnew / .pacsave)"
    echo "------------------------------------------------------------------"
    local pacfiles
    pacfiles=$(find /etc -regextype posix-extended -regex '.*\.(pacnew|pacsave)' 2>/dev/null || true)
    if [ -n "$pacfiles" ]; then
      echo "Atenção: Os seguintes arquivos precisam de revisão/merge:"
      echo "$pacfiles"
      echo "Dica: Utilize a ferramenta 'pacdiff' para revisar."
    else
      echo "✓ Nenhum arquivo .pacnew ou .pacsave pendente em /etc."
    fi
    echo ""

    echo "[4] ERROS CRÍTICOS DE KERNEL / HARDWARE (Boot atual)"
    echo "------------------------------------------------------------------"
    local journal_errors
    journal_errors=$(journalctl -p 3 -xb --no-pager -q 2>/dev/null | tail -n 25 || true)
    if [ -n "$journal_errors" ]; then
      echo "Últimos erros registrados pelo kernel/sistema:"
      echo "$journal_errors"
    else
      echo "✓ Nenhum erro crítico (nível erro/falha) no boot atual."
    fi
    echo ""

    echo "=================================================================="
    echo "Fim do relatório. Pressione [ESC] ou [ENTER] para voltar."
  } >"$tmpfile"

  dialog \
    --backtitle "Arch Linux - Central de Limpeza e Otimização" \
    --title " Diagnóstico de Saúde e Compatibilidade " \
    --textbox "$tmpfile" 22 75

  rm -f "$tmpfile"
}

# ==============================================================================
# Provisionamento Multi-Distro via Repositório Central Git
# ==============================================================================

detect_package_manager() {
  if command -v pacman &>/dev/null; then
    PKG_FAMILY="arch"
    PKG_INSTALL="sudo pacman -S --needed --noconfirm"
  elif command -v apt-get &>/dev/null; then
    PKG_FAMILY="debian"
    PKG_INSTALL="sudo apt-get install -y"
  elif command -v dnf &>/dev/null; then
    PKG_FAMILY="fedora"
    PKG_INSTALL="sudo dnf install -y"
  elif command -v zypper &>/dev/null; then
    PKG_FAMILY="zypper"
    PKG_INSTALL="sudo zypper install -y"
  else
    PKG_FAMILY="unknown"
    PKG_INSTALL=""
  fi
}

sync_dev_repo() {
  detect_package_manager
  if [ "$PKG_FAMILY" = "unknown" ]; then
    dialog --msgbox "Gerenciador de pacotes da distribuição não suportado." 6 55
    return 1
  fi

  local repo_url=""
  if [ -f "$CONFIG_FILE" ]; then
    repo_url=$(head -n 1 "$CONFIG_FILE")
  fi

  if [ -z "$repo_url" ]; then
    exec 3>&1
    repo_url=$(dialog \
      --backtitle "Provisionamento de Ambiente Dev" \
      --title " Repositório Central de Presets " \
      --inputbox "Informe a URL Git do repositório de presets:" 9 65 \
      "https://github.com/seu-usuario/dev-environments.git" \
      2>&1 1>&3)
    local status=$?
    exec 3>&-

    [ $status -ne 0 ] || [ -z "$repo_url" ] && return 1

    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "$repo_url" >"$CONFIG_FILE"
  fi

  dialog --infobox "Sincronizando repositório de presets..." 4 50
  if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull --quiet 2>/dev/null || true
  else
    mkdir -p "$REPO_DIR"
    if ! git clone --quiet "$repo_url" "$REPO_DIR" 2>/dev/null; then
      dialog --msgbox "Falha ao clonar repositório. Verifique a URL e sua conexão." 6 55
      rm -rf "$REPO_DIR"
      return 1
    fi
  fi
  return 0
}

install_dev_environment() {
  sync_dev_repo || return

  local target_dir="$REPO_DIR/$PKG_FAMILY"
  if [ ! -d "$target_dir" ]; then
    target_dir="$REPO_DIR"
  fi

  local profiles=()
  for file in "$target_dir"/*.txt; do
    [ -e "$file" ] || continue
    local name
    name=$(basename "$file" .txt)
    profiles+=("$name" "Perfil de pacotes: $name")
  done

  if [ ${#profiles[@]} -eq 0 ]; then
    dialog --msgbox "Nenhum arquivo de perfil (.txt) encontrado em $target_dir." 6 55
    return
  fi

  exec 3>&1
  local chosen_profile
  chosen_profile=$(dialog \
    --backtitle "Provisionamento: $PKG_FAMILY" \
    --title " Escolha o Perfil " \
    --menu "Selecione o perfil que deseja provisionar:" 15 60 6 \
    "${profiles[@]}" \
    2>&1 1>&3)
  local status=$?
  exec 3>&-

  [ $status -ne 0 ] || [ -z "$chosen_profile" ] && return

  local profile_path="$target_dir/${chosen_profile}.txt"
  local checklist_items=()

  while IFS='|' read -r pkg desc || [ -n "$pkg" ]; do
    [[ "$pkg" =~ ^#.*$ || -z "$pkg" ]] && continue
    pkg=$(echo "$pkg" | xargs)
    desc=$(echo "$desc" | xargs)
    [ -z "$desc" ] && desc="Instalar $pkg"
    checklist_items+=("$pkg" "$desc" "ON")
  done <"$profile_path"

  exec 3>&1
  local selected_packages
  selected_packages=$(dialog --separate-output \
    --backtitle "Provisionamento: $chosen_profile ($PKG_FAMILY)" \
    --title " Seleção de Pacotes " \
    --checklist "Marque os pacotes com [ESPAÇO]:" 20 70 12 \
    "${checklist_items[@]}" \
    2>&1 1>&3)
  status=$?
  exec 3>&-

  [ $status -ne 0 ] || [ -z "$selected_packages" ] && return

  local pkg_list
  pkg_list=$(echo "$selected_packages" | tr '\n' ' ')

  clear
  echo "========================================================"
  echo "      INSTALANDO AMBIENTE: $chosen_profile              "
  echo "========================================================"
  echo "Gerenciador : $PKG_FAMILY"
  echo "Comando     : $PKG_INSTALL"
  echo "Pacotes     : $pkg_list"
  echo "========================================================"
  echo ""

  $PKG_INSTALL $pkg_list

  echo ""
  read -rp "Instalação concluída. Pressione [ENTER] para voltar..."
}

# ==============================================================================
# Módulo de Runtimes com Mise (Universal)
# ==============================================================================

ensure_mise_installed() {
  if command -v mise &>/dev/null; then
    return 0
  fi

  dialog --infobox "Mise não detectado. Baixando binário universal..." 4 55

  if curl -fsSL https://mise.run | sh; then
    export PATH="$HOME/.local/bin:$PATH"
  else
    dialog --msgbox "Falha ao baixar o Mise. Verifique a conexão com a internet." 6 55
    return 1
  fi

  local user_shell
  user_shell=$(basename "$SHELL")
  local rc_file="$HOME/.bashrc"
  [ "$user_shell" = "zsh" ] && rc_file="$HOME/.zshrc"

  if ! grep -q 'mise activate' "$rc_file" 2>/dev/null; then
    echo -e '\n# Ativação do gerenciador de runtimes Mise' >>"$rc_file"
    echo 'eval "$(~/.local/bin/mise activate '"$user_shell"')"' >>"$rc_file"
  fi

  return 0
}

inspect_mise_storage() {
  local tmpfile
  tmpfile=$(mktemp)
  local installs_dir="$HOME/.local/share/mise/installs"
  local cache_dir="$HOME/.cache/mise"

  {
    echo "=================================================================="
    echo "               USO DE DISCO POR RUNTIME DO MISE                   "
    echo "=================================================================="
    echo ""
    echo "TAMANHO     LINGUAGEM / VERSÃO"
    echo "------------------------------------------------------------------"

    if [ -d "$installs_dir" ] && [ -n "$(ls -A "$installs_dir" 2>/dev/null)" ]; then
      du -h -d 2 "$installs_dir" 2>/dev/null | sort -hr | while read -r size path; do
        [ "$path" = "$installs_dir" ] && continue
        rel_path="${path#$installs_dir/}"
        printf "%-10s  %s\n" "$size" "$rel_path"
      done
    else
      echo "Nenhuma runtime instalada encontrada."
    fi

    echo ""
    echo "TOTAIS ACUMULADOS"
    echo "------------------------------------------------------------------"
    if [ -d "$installs_dir" ]; then
      echo "Diretório de Instalações : $(du -sh "$installs_dir" 2>/dev/null | cut -f1)"
    fi
    if [ -d "$cache_dir" ]; then
      echo "Diretório de Cache       : $(du -sh "$cache_dir" 2>/dev/null | cut -f1)"
    fi
    echo ""
    echo "Pressione [ESC] ou [ENTER] para voltar."
  } >"$tmpfile"

  dialog \
    --backtitle "Mise - Gerenciamento de Armazenamento" \
    --title " Espaço em Disco das Runtimes " \
    --textbox "$tmpfile" 20 68

  rm -f "$tmpfile"
}

uninstall_mise_runtime() {
  ensure_mise_installed || return

  local installs_dir="$HOME/.local/share/mise/installs"
  if [ ! -d "$installs_dir" ] || [ -z "$(ls -A "$installs_dir" 2>/dev/null)" ]; then
    dialog --msgbox "Nenhuma runtime instalada encontrada para remoção." 6 55
    return
  fi

  local items=()
  for tool_dir in "$installs_dir"/*; do
    [ -d "$tool_dir" ] || continue
    local tool
    tool=$(basename "$tool_dir")

    for ver_dir in "$tool_dir"/*; do
      [ -d "$ver_dir" ] || continue
      local ver
      ver=$(basename "$ver_dir")
      local size
      size=$(du -sh "$ver_dir" 2>/dev/null | cut -f1)
      items+=("${tool}@${ver}" "Espaço: ${size}" "OFF")
    done
  done

  if [ ${#items[@]} -eq 0 ]; then
    dialog --msgbox "Nenhuma versão encontrada para desinstalação." 6 55
    return
  fi

  exec 3>&1
  local selected
  selected=$(dialog --separate-output \
    --backtitle "Mise - Desinstalação de Runtimes" \
    --title " Selecionar Versões para Remover " \
    --checklist "Marque com [ESPAÇO] e confirme com [ENTER]:" 18 65 8 \
    "${items[@]}" \
    2>&1 1>&3)
  local status=$?
  exec 3>&-

  [ $status -ne 0 ] || [ -z "$selected" ] && return

  local formatted_list
  formatted_list=$(echo "$selected" | sed 's/^/  • /')

  dialog \
    --backtitle "Mise - Confirmar Exclusão" \
    --title " Confirmação de Remoção " \
    --yesno "Deseja realmente desinstalar as seguintes versões?\n\n$formatted_list\n\nEssa ação liberará o espaço em disco imediatamente." 14 60
  local confirm_status=$?

  [ $confirm_status -ne 0 ] && return

  clear
  echo "========================================================"
  echo "           DESINSTALANDO RUNTIMES DO MISE               "
  echo "========================================================"
  while IFS= read -r runtime; do
    [ -z "$runtime" ] && continue
    echo "--> Removendo runtime: $runtime..."
    if ! mise uninstall "$runtime" 2>/dev/null; then
      local tool_name="${runtime%@*}"
      local ver_name="${runtime#*@}"
      rm -rf "${installs_dir}/${tool_name}/${ver_name}" 2>/dev/null || true
      echo "✓ Removido diretamente do disco: $runtime"
    fi
  done <<<"$selected"

  echo ""
  read -rp "Desinstalação concluída. Pressione [ENTER] para voltar..."
}

manage_mise_runtimes() {
  ensure_mise_installed || return

  exec 3>&1
  local action
  action=$(dialog \
    --backtitle "Gerenciador Universal de Runtimes (Mise)" \
    --title " Runtimes & Linguagens " \
    --menu "Escolha uma operação:" 17 65 5 \
    "1" "Sincronizar mise.toml do repositório central" \
    "2" "Seleção interativa de runtimes (Node, Python, Go...)" \
    "3" "Listar versões ativas no ambiente (mise current)" \
    "4" "Inspecionar espaço em disco ocupado pelas runtimes" \
    "5" "Desinstalar versão específica de runtime" \
    2>&1 1>&3)
  local status=$?
  exec 3>&-

  [ $status -ne 0 ] && return

  case "$action" in
  1)
    local remote_config="$REPO_DIR/mise.toml"
    if [ ! -f "$remote_config" ]; then
      sync_dev_repo || return
    fi

    if [ -f "$remote_config" ]; then
      clear
      echo "--> Aplicando $remote_config..."
      mkdir -p "$HOME/.config/mise"
      cp "$remote_config" "$HOME/.config/mise/config.toml"
      mise install -y
      echo ""
      read -rp "Runtimes sincronizadas. Pressione [ENTER]..."
    else
      dialog --msgbox "Arquivo mise.toml não encontrado no repositório." 6 55
    fi
    ;;

  2)
    exec 3>&1
    local choices
    choices=$(dialog --separate-output \
      --backtitle "Mise - Seleção de Runtimes" \
      --title " Escolha as Linguagens " \
      --checklist "Marque as stacks com [ESPAÇO]:" 18 65 6 \
      "node@lts" "Node.js (Versão LTS estável)" ON \
      "pnpm@latest" "PNPM Package Manager" ON \
      "python@latest" "Python 3 (Última versão estável)" ON \
      "go@latest" "Go / Golang (Última versão)" ON \
      "rust@latest" "Rust Toolchain (rustc/cargo)" OFF \
      "bun@latest" "Bun Runtime & Bundler" OFF \
      2>&1 1>&3)
    status=$?
    exec 3>&-

    [ $status -ne 0 ] || [ -z "$choices" ] && return

    clear
    echo "========================================================"
    echo "           INSTALANDO RUNTIMES VIA MISE                 "
    echo "========================================================"
    while IFS= read -r runtime; do
      [ -z "$runtime" ] && continue
      echo "--> Configurando e instalando: $runtime..."
      mise use --global "$runtime"
    done <<<"$choices"

    echo ""
    read -rp "Instalação concluída. Pressione [ENTER] para voltar..."
    ;;

  3)
    local list_output
    list_output=$(mise current 2>&1 || true)
    dialog \
      --backtitle "Mise - Runtimes Ativas" \
      --title " Versões em Uso " \
      --msgbox "Ferramentas ativas no ambiente:\n\n${list_output:-Nenhuma runtime configurada ainda.}" 16 65
    ;;

  4)
    inspect_mise_storage
    ;;

  5)
    uninstall_mise_runtime
    ;;
  esac
}

# ==============================================================================
# Executores de Limpeza
# ==============================================================================

run_general() {
  clear
  sudo -v
  local before
  before=$(get_available_space_kb)

  clean_orphans
  clean_pacman
  clean_aur
  clean_systemd
  clean_trash
  clean_flatpak

  pause_screen "$before"
}

run_dev() {
  clear
  local before
  before=$(get_available_space_kb)

  clean_docker
  clean_mise
  clean_dev_caches
  clean_ide_caches

  pause_screen "$before"
}

run_all() {
  clear
  sudo -v
  local before
  before=$(get_available_space_kb)

  clean_orphans
  clean_pacman
  clean_aur
  clean_systemd
  clean_trash
  clean_flatpak
  clean_docker
  clean_mise
  clean_dev_caches
  clean_ide_caches

  pause_screen "$before"
}

run_custom() {
  exec 3>&1
  choices=$(dialog --separate-output \
    --backtitle "Arch Linux - Central de Limpeza" \
    --title " Seleção Personalizada " \
    --checklist "Marque os itens com [ESPAÇO] e confirme com [ENTER]:" 19 68 10 \
    1 "Pacotes Órfãos (pacman -Qtdq)" ON \
    2 "Cache do Pacman (paccache)" ON \
    3 "Cache do AUR (Paru/Yay)" ON \
    4 "Logs do Systemd (journalctl)" ON \
    5 "Lixeira e Miniaturas do Usuário" ON \
    6 "Flatpaks não utilizados" OFF \
    7 "Containers (Docker/Podman Prune)" OFF \
    8 "Runtimes órfãs e Cache do Mise" ON \
    9 "Caches de Linguagens (npm, pip, go, cargo)" ON \
    10 "Caches de IDEs (VS Code, JetBrains)" ON \
    2>&1 1>&3)
  exit_status=$?
  exec 3>&-

  if [ $exit_status -ne 0 ] || [ -z "$choices" ]; then
    return
  fi

  clear
  sudo -v
  local before
  before=$(get_available_space_kb)

  while IFS= read -r choice; do
    case "$choice" in
    1) clean_orphans ;;
    2) clean_pacman ;;
    3) clean_aur ;;
    4) clean_systemd ;;
    5) clean_trash ;;
    6) clean_flatpak ;;
    7) clean_docker ;;
    8) clean_mise ;;
    9) clean_dev_caches ;;
    10) clean_ide_caches ;;
    esac
  done <<<"$choices"

  pause_screen "$before"
}

# ==============================================================================
# Menu Principal em Loop
# ==============================================================================

while true; do
  exec 3>&1
  SELECAO=$(dialog \
    --backtitle "Central de Manutenção e Otimização Dev" \
    --title " Menu Principal " \
    --clear \
    --cancel-label "Sair" \
    --menu "Escolha uma operação:" 19 65 9 \
    "1" "Limpeza Geral (Pacman, AUR, Logs, Lixeira)" \
    "2" "Limpeza de Desenvolvimento (Docker, Mise, Caches, IDEs)" \
    "3" "Limpeza Personalizada (Seleção modular de itens)" \
    "4" "Limpeza Completa (Geral + Desenvolvimento)" \
    "5" "Inspecionar Maiores Pacotes (Top 50 instalados)" \
    "6" "Diagnóstico de Saúde e Integridade do Sistema" \
    "7" "Instalar Pacotes da Distro (Git Presets por OS)" \
    "8" "Gerenciar Runtimes Universais (Mise: Node, Python, Go)" \
    "0" "Sair" \
    2>&1 1>&3)
  exit_status=$?
  exec 3>&-

  if [ $exit_status -ne 0 ] || [ "$SELECAO" = "0" ]; then
    clear
    echo "Sessão encerrada."
    exit 0
  fi

  case "$SELECAO" in
  1) run_general ;;
  2) run_dev ;;
  3) run_custom ;;
  4) run_all ;;
  5) inspect_heavy_packages ;;
  6) diagnose_system ;;
  7) install_dev_environment ;;
  8) manage_mise_runtimes ;;
  esac
done
