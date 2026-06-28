#!/usr/bin/env bash
# install.sh — установка и обновление набора навыков 1c-bitrix-cms
#              для Claude Code и Codex.
#
# Быстрый старт (последний релиз с GitHub):
#   curl -fsSL https://raw.githubusercontent.com/vrtalex/1c-bitrix-cms-skill/main/install.sh | bash
#
# Примеры:
#   bash install.sh --both
#   bash install.sh --claude --version 1.0.0
#   bash install.sh --local --both          # из текущего клона, без скачивания
#   bash install.sh --check                  # есть ли обновление
#   bash install.sh --dry-run --auto         # показать план без изменений
set -euo pipefail

# --- Константы --------------------------------------------------------------
REPO="vrtalex/1c-bitrix-cms-skill"
PACK_NAME="1c-bitrix-cms"
# 12 каталогов навыков, которые входят в набор.
SKILL_DIRS="
1c-bitrix-cms
1c-bitrix-cms-setup
1c-bitrix-cms-settings
1c-bitrix-cms-template
1c-bitrix-cms-content
1c-bitrix-cms-seo
1c-bitrix-cms-commerce
1c-bitrix-cms-deploy
1c-bitrix-cms-security
1c-bitrix-cms-quality
1c-bitrix-cms-update
1c-bitrix-cms-rest
"
# Орхестратор и образцовый узел базы знаний — для пост-проверки раскладки.
ORCHESTRATOR_REL="skills/${PACK_NAME}/SKILL.md"
SAMPLE_KB_REL="shared/kb/00-overview.md"
VERSION_MARKER=".1c-bitrix-cms.version"

CLAUDE_HOME="${HOME}/.claude"
CODEX_HOME_DIR="${CODEX_HOME:-${HOME}/.codex}"

# --- Параметры по умолчанию -------------------------------------------------
TARGET_MODE="auto"
REQUESTED_VERSION=""
USE_LOCAL=false
CHECK_ONLY=false
DRY_RUN=false

# Каталог клона (где лежит этот скрипт) — для режима --local.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"

# --- Вывод ------------------------------------------------------------------
print_step()  { printf "\n\033[1;34m==>\033[0m %s\n" "$1"; }
print_ok()    { printf "  \033[1;32mOK\033[0m %s\n" "$1"; }
print_warn()  { printf "  \033[1;33m!\033[0m %s\n" "$1"; }
print_error() { printf "\n\033[1;31mОшибка:\033[0m %s\n" "$1" >&2; }

usage() {
  cat <<'EOF'
Использование:
  bash install.sh [--auto|--claude|--codex|--both] [--version X.Y.Z]
                  [--local] [--check] [--dry-run]

Цели установки:
  --auto       во все обнаруженные homes (по умолчанию): ~/.claude и/или Codex
  --claude     только в ~/.claude
  --codex      только в $CODEX_HOME (или ~/.codex)
  --both       и в Claude, и в Codex

Источник:
  --version X.Y.Z   установить конкретный релиз (по умолчанию — последний)
  --local           копировать из текущего клона (./skills и ./shared),
                    без обращения к сети

Режимы:
  --check      вывести "UPDATE_AVAILABLE local=X remote=Y" или "UP_TO_DATE"
               и выйти (ничего не меняет)
  --dry-run    показать планируемые операции без изменений на диске
  -h, --help   эта справка

Раскладка после установки (важно для относительных путей ../../shared):
  <HOME>/skills/<имя-навыка>/SKILL.md
  <HOME>/shared/...
EOF
}

# --- Утилиты версий ---------------------------------------------------------
normalize_version() {
  local v="${1#v}"
  printf '%s' "${v//[[:space:]]/}"
}

version_to_tag() {
  printf 'v%s' "$(normalize_version "$1")"
}

# Числовое представление X.Y.Z для сравнения «больше».
version_to_num() {
  local v major minor patch IFS=.
  v="$(normalize_version "$1")"
  read -r major minor patch <<<"$v"
  printf '%05d%05d%05d' "${major:-0}" "${minor:-0}" "${patch:-0}"
}

version_gt() {
  [[ "$(version_to_num "$1")" > "$(version_to_num "$2")" ]]
}

# --- Источники версии -------------------------------------------------------
# Локальная версия из клона (release/VERSION → VERSION на верхнем уровне пакета).
local_clone_version() {
  if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
    tr -d '[:space:]' < "${SCRIPT_DIR}/VERSION"
  else
    echo ""
  fi
}

# Установленная версия в данном HOME.
installed_version() {
  local home="$1"
  local f="${home}/skills/${VERSION_MARKER}"
  if [[ -f "$f" ]]; then
    tr -d '[:space:]' < "$f"
  else
    echo ""
  fi
}

# Последний тег релиза с GitHub (через редирект /releases/latest).
fetch_latest_release_tag() {
  local url effective
  url="https://github.com/${REPO}/releases/latest"
  effective="$(curl -fsSL -o /dev/null -w '%{url_effective}' "$url" 2>/dev/null || true)"
  if [[ "$effective" == *"/releases/tag/"* ]]; then
    printf '%s' "${effective##*/}"
    return 0
  fi
  return 1
}

# Версия из ветки main (raw VERSION) — запасной источник для --check.
fetch_main_version() {
  curl -fsSL --retry 3 --retry-delay 2 \
    "https://raw.githubusercontent.com/${REPO}/main/VERSION" 2>/dev/null \
    | tr -d '[:space:]'
}

# Удалённая версия: тег релиза, иначе версия из main.
resolve_remote_version() {
  local tag ver
  tag="$(fetch_latest_release_tag || true)"
  if [[ -n "$tag" ]]; then
    normalize_version "$tag"
    return 0
  fi
  ver="$(fetch_main_version || true)"
  if [[ -n "$ver" ]]; then
    normalize_version "$ver"
    return 0
  fi
  return 1
}

# --- Цели установки ---------------------------------------------------------
# Печатает строки "Имя|путь_home" по выбранному режиму.
detect_targets() {
  case "$TARGET_MODE" in
    claude) printf 'Claude|%s\n' "$CLAUDE_HOME" ;;
    codex)  printf 'Codex|%s\n'  "$CODEX_HOME_DIR" ;;
    both)
      printf 'Claude|%s\n' "$CLAUDE_HOME"
      printf 'Codex|%s\n'  "$CODEX_HOME_DIR"
      ;;
    auto)
      local found=0
      if [[ -d "$CLAUDE_HOME" ]]; then
        printf 'Claude|%s\n' "$CLAUDE_HOME"; found=1
      fi
      if [[ -n "${CODEX_HOME:-}" || -d "${HOME}/.codex" ]]; then
        printf 'Codex|%s\n' "$CODEX_HOME_DIR"; found=1
      fi
      if [[ "$found" -eq 0 ]]; then
        # Ни один home не найден — ставим в оба пути по умолчанию.
        printf 'Claude|%s\n' "$CLAUDE_HOME"
        printf 'Codex|%s\n'  "$CODEX_HOME_DIR"
      fi
      ;;
    *)
      print_error "неизвестный режим цели: $TARGET_MODE"
      exit 2
      ;;
  esac
}

# --- Получение исходников (skills/ + shared/) -------------------------------
# Готовит каталог-источник с подкаталогами skills/ и shared/.
# Печатает путь к источнику в stdout; диагностика идёт в stderr.
prepare_source() {
  local stage="$1"  # рабочий tmp-каталог

  if [[ "$USE_LOCAL" == true ]]; then
    if [[ ! -d "${SCRIPT_DIR}/skills" || ! -d "${SCRIPT_DIR}/shared" ]]; then
      print_error "режим --local: рядом со скриптом нет skills/ и shared/ (${SCRIPT_DIR})"
      return 1
    fi
    printf '%s' "$SCRIPT_DIR"
    return 0
  fi

  # Сетевой режим: скачиваем тарбол релиза и распаковываем.
  local tag archive_url out extracted
  if [[ -n "$REQUESTED_VERSION" ]]; then
    tag="$(version_to_tag "$REQUESTED_VERSION")"
  else
    tag="$(fetch_latest_release_tag || true)"
    [[ -n "$tag" ]] || { print_error "не удалось определить последний релиз ${REPO}"; return 1; }
  fi

  archive_url="https://github.com/${REPO}/archive/refs/tags/${tag}.tar.gz"
  out="${stage}/pack.tar.gz"
  print_step "Скачивание ${tag}" >&2
  if ! curl -fsSL --retry 3 --retry-delay 2 "$archive_url" -o "$out"; then
    print_error "не удалось скачать ${archive_url}"
    return 1
  fi
  tar -xzf "$out" -C "$stage"
  # Внутри тарбола — один каталог <repo>-<tag без v>/.
  extracted="$(find "$stage" -mindepth 1 -maxdepth 1 -type d | head -1)"
  if [[ -z "$extracted" || ! -d "${extracted}/skills" || ! -d "${extracted}/shared" ]]; then
    print_error "неожиданная структура тарбола (нет skills/ и shared/)"
    return 1
  fi
  printf '%s' "$extracted"
}

# --- Установка в один HOME --------------------------------------------------
install_into_home() {
  local name="$1" home="$2" src="$3" version="$4"
  local dest_skills="${home}/skills"
  local dest_shared="${home}/shared"

  if [[ "$DRY_RUN" == true ]]; then
    print_step "[dry-run] ${name}: ${home}"
    local s
    for s in $SKILL_DIRS; do
      printf "    cp -R %s -> %s\n" "${src}/skills/${s}" "${dest_skills}/${s}"
    done
    printf "    cp -R %s -> %s\n" "${src}/shared" "${dest_shared}"
    printf "    write version %s -> %s\n" "$version" "${dest_skills}/${VERSION_MARKER}"
    return 0
  fi

  print_step "${name}: установка ${version} -> ${home}"
  mkdir -p "$dest_skills"

  # Атомарно: собираем во временной зоне рядом, затем переносим на место.
  local s tmp
  for s in $SKILL_DIRS; do
    if [[ ! -d "${src}/skills/${s}" ]]; then
      print_error "${name}: в источнике нет навыка ${s}"
      return 1
    fi
    tmp="${dest_skills}/.tmp-${s}.$$"
    rm -rf "$tmp"
    cp -R "${src}/skills/${s}" "$tmp"
    rm -rf "${dest_skills}/${s}"
    mv "$tmp" "${dest_skills}/${s}"
  done
  print_ok "${name}: 12 навыков -> ${dest_skills}/"

  tmp="${dest_shared}.tmp.$$"
  rm -rf "$tmp"
  cp -R "${src}/shared" "$tmp"
  rm -rf "$dest_shared"
  mv "$tmp" "$dest_shared"
  print_ok "${name}: база знаний -> ${dest_shared}/"

  printf '%s\n' "$version" > "${dest_skills}/${VERSION_MARKER}"

  # Пост-проверка: орхестратор на месте и ../../shared разрешается из навыка.
  if [[ ! -f "${home}/${ORCHESTRATOR_REL}" ]]; then
    print_error "${name}: после установки нет ${ORCHESTRATOR_REL}"
    return 1
  fi
  # Из каталога навыка путь ../../shared/kb/00-overview.md должен указывать на файл.
  local resolved="${home}/skills/${PACK_NAME}/../../${SAMPLE_KB_REL}"
  if [[ ! -f "$resolved" ]]; then
    print_error "${name}: ../../shared не разрешается (нет ${SAMPLE_KB_REL})"
    return 1
  fi
  print_ok "${name}: ../../shared/kb/00-overview.md разрешается из навыка"
}

# --- Режим --check ----------------------------------------------------------
run_check() {
  # Локальная версия: установленная в первой обнаруженной цели, иначе клон.
  local local_ver remote_ver line home
  local_ver=""
  while IFS='|' read -r _ home; do
    [[ -n "$home" ]] || continue
    local_ver="$(installed_version "$home")"
    [[ -n "$local_ver" ]] && break
  done <<EOF
$(detect_targets)
EOF
  if [[ -z "$local_ver" ]]; then
    local_ver="$(local_clone_version)"
    [[ -n "$local_ver" ]] || local_ver="none"
  fi

  if ! remote_ver="$(resolve_remote_version)"; then
    echo "CHECK_FAILED reason=remote_version_unavailable"
    return 0
  fi

  if [[ "$local_ver" == "none" ]] || version_gt "$remote_ver" "$local_ver"; then
    echo "UPDATE_AVAILABLE local=${local_ver} remote=${remote_ver}"
  else
    echo "UP_TO_DATE local=${local_ver} remote=${remote_ver}"
  fi
}

# --- Разбор аргументов ------------------------------------------------------
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --auto)    TARGET_MODE="auto"; shift ;;
    --claude)  TARGET_MODE="claude"; shift ;;
    --codex)   TARGET_MODE="codex"; shift ;;
    --both)    TARGET_MODE="both"; shift ;;
    --local)   USE_LOCAL=true; shift ;;
    --check)   CHECK_ONLY=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --version)
      [[ "$#" -ge 2 ]] || { print_error "--version требует значение"; exit 2; }
      REQUESTED_VERSION="$(normalize_version "$2")"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

# curl нужен и для --check, и для сетевой установки.
if [[ "$USE_LOCAL" == false || "$CHECK_ONLY" == true ]]; then
  command -v curl >/dev/null 2>&1 || { print_error "требуется curl"; exit 1; }
fi
if [[ "$USE_LOCAL" == false && "$CHECK_ONLY" == false ]]; then
  command -v tar >/dev/null 2>&1 || { print_error "требуется tar"; exit 1; }
fi

# --- Режим проверки обновления ----------------------------------------------
if [[ "$CHECK_ONLY" == true ]]; then
  run_check
  exit 0
fi

# --- Определяем целевую версию для установки --------------------------------
INSTALL_VERSION=""
if [[ "$USE_LOCAL" == true ]]; then
  INSTALL_VERSION="$(local_clone_version)"
  [[ -n "$INSTALL_VERSION" ]] || INSTALL_VERSION="0.0.0"
elif [[ -n "$REQUESTED_VERSION" ]]; then
  INSTALL_VERSION="$REQUESTED_VERSION"
else
  if ! INSTALL_VERSION="$(resolve_remote_version)"; then
    print_error "не удалось определить версию релиза"
    exit 1
  fi
fi

print_step "Набор ${PACK_NAME} ${INSTALL_VERSION}"
if [[ "$USE_LOCAL" == true ]]; then
  print_ok "источник: локальный клон ${SCRIPT_DIR}"
else
  print_ok "источник: релиз github.com/${REPO}"
fi

# --- Подготовка источника ---------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ "$DRY_RUN" == true && "$USE_LOCAL" == false ]]; then
  # В dry-run без --local не качаем — показываем план с условным источником.
  SOURCE="<распакованный релиз ${INSTALL_VERSION}>"
else
  SOURCE="$(prepare_source "$WORK")"
fi

# --- Установка по целям -----------------------------------------------------
INSTALLED_LIST=""
while IFS='|' read -r name home; do
  [[ -n "$name" && -n "$home" ]] || continue
  install_into_home "$name" "$home" "$SOURCE" "$INSTALL_VERSION"
  INSTALLED_LIST="${INSTALLED_LIST}  - ${name}: ${home}/skills/ + ${home}/shared/"$'\n'
done <<EOF
$(detect_targets)
EOF

# --- Итог -------------------------------------------------------------------
if [[ "$DRY_RUN" == true ]]; then
  printf "\n\033[1;33mDry-run:\033[0m изменения на диск не вносились.\n"
  exit 0
fi

printf "\n\033[1;32mГотово!\033[0m Набор %s %s установлен.\n" "$PACK_NAME" "$INSTALL_VERSION"
printf "Цели:\n%s" "$INSTALLED_LIST"
printf "Точка входа: навык %s (орхестратор).\n" "$PACK_NAME"
printf "Проверка обновлений: bash install.sh --check\n\n"
