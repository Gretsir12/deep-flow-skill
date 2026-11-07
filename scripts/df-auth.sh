#!/usr/bin/env bash
# df-auth.sh — хранение и выдача учётных данных DeepFlow.
#
# Ключ не хранится в Skill: скрипт кладёт его в защищённое хранилище ОС и
# отдаёт по запросу (stdout) обёртке df.sh. В чат, в файлы репозитория и в
# аргументы командной строки ключ не попадает.
#
# Команды:
#   set             прочитать ключ из stdin и сохранить (перезаписывает)
#   key             напечатать ключ (используется df.sh, не для человека)
#   url [<url>]     показать или сохранить базовый URL инсталляции
#   status          что настроено, откуда берётся ключ (маска)
#   test            GET /public/projects — проверка ключа и URL
#   rm              удалить ключ из всех хранилищ
#
# Хранилища:
#   macOS    — Keychain (service deepflow-api-key, account $USER)
#   Linux    — Secret Service через secret-tool (если установлен)
#   Windows  — DPAPI через df-auth.ps1 (делегирование из Git Bash)
#   остальное — файл 0600: ${XDG_CONFIG_HOME:-~/.config}/deepflow/api-key
#
# Переопределения окружения (ничего не сохраняют):
#   DEEPFLOW_API_KEY       ключ на один запуск (CI, отладка)
#   DEEPFLOW_API_KEY_FILE  путь к файлу с ключом
#   DEEPFLOW_API_URL       базовый URL на один запуск
#   DEEPFLOW_KEY_STORE     auto|keychain|secret-service|file
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/deepflow"
KEY_FILE="$CONFIG_DIR/api-key"
URL_FILE="$CONFIG_DIR/api-url"
SERVICE="deepflow-api-key"
ACCOUNT="${USER:-$(id -un)}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_URL="http://localhost:8080"

err() { printf 'df-auth: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

platform() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin) echo macos ;;
    Linux) echo linux ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo other ;;
  esac
}

PLATFORM="$(platform)"

# На Windows (Git Bash/MSYS) секреты хранит df-auth.ps1 через DPAPI:
# bash-ветка не умеет ни DPAPI, ни реестр. Пути берём из APPDATA.
ps_exe() {
  if have powershell.exe; then
    command -v powershell.exe
    return 0
  fi
  local candidate="${SystemRoot:-/c/Windows}/System32/WindowsPowerShell/v1.0/powershell.exe"
  [[ -x "$candidate" ]] && {
    printf '%s' "$candidate"
    return 0
  }
  return 1
}

if [[ "$PLATFORM" == windows ]] && [[ -f "$SELF_DIR/df-auth.ps1" ]] && powershell_bin="$(ps_exe)"; then
  exec "$powershell_bin" -NoProfile -ExecutionPolicy Bypass -File "$SELF_DIR/df-auth.ps1" "$@"
fi

# ---------------------------------------------------------------- keychain

keychain_get() {
  [[ "$PLATFORM" == macos ]] || return 1
  have security || return 1
  local value
  value="$(security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w 2>/dev/null)" || return 1
  [[ -n "$value" ]] || return 1
  printf '%s' "$value"
}

# --------------------------------------------------------- secret-service

secret_service_get() {
  [[ "$PLATFORM" == linux ]] || return 1
  have secret-tool || return 1
  local value
  value="$(secret-tool lookup service "$SERVICE" account "$ACCOUNT" 2>/dev/null)" || return 1
  [[ -n "$value" ]] || return 1
  printf '%s' "$value"
}

# -------------------------------------------------------------------- file

file_get() {
  [[ -f "$KEY_FILE" ]] || return 1
  local value
  value="$(tr -d '\r\n' <"$KEY_FILE")" || return 1
  [[ -n "$value" ]] || return 1
  printf '%s' "$value"
}

# --------------------------------------------------------------- resolving

resolve_key() {
  if [[ -n "${DEEPFLOW_API_KEY:-}" ]]; then
    printf '%s' "$DEEPFLOW_API_KEY"
    return 0
  fi
  if [[ -n "${DEEPFLOW_API_KEY_FILE:-}" ]]; then
    [[ -r "$DEEPFLOW_API_KEY_FILE" ]] || die "DEEPFLOW_API_KEY_FILE is not readable"
    tr -d '\r\n' <"$DEEPFLOW_API_KEY_FILE"
    return 0
  fi
  keychain_get && return 0
  secret_service_get && return 0
  file_get && return 0
  return 1
}

key_source() {
  if [[ -n "${DEEPFLOW_API_KEY:-}" ]]; then
    echo "env: DEEPFLOW_API_KEY (не сохранён)"
  elif [[ -n "${DEEPFLOW_API_KEY_FILE:-}" ]]; then
    echo "file: $DEEPFLOW_API_KEY_FILE"
  elif keychain_get >/dev/null; then
    echo "keychain: service=$SERVICE account=$ACCOUNT"
  elif secret_service_get >/dev/null; then
    echo "secret-service: service=$SERVICE"
  elif file_get >/dev/null; then
    echo "file: $KEY_FILE"
  else
    echo "none"
  fi
}

resolve_url() {
  if [[ -n "${DEEPFLOW_API_URL:-}" ]]; then
    printf '%s' "$DEEPFLOW_API_URL"
    return 0
  fi
  if [[ -f "$URL_FILE" ]]; then
    local value
    value="$(tr -d '\r\n' <"$URL_FILE")"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  fi
  printf '%s' "$DEFAULT_URL"
}

url_source() {
  if [[ -n "${DEEPFLOW_API_URL:-}" ]]; then
    echo "env: DEEPFLOW_API_URL"
  elif [[ -f "$URL_FILE" && -n "$(tr -d '\r\n' <"$URL_FILE")" ]]; then
    echo "file: $URL_FILE"
  else
    echo "default: $DEFAULT_URL"
  fi
}

# ----------------------------------------------------------------- storing

write_file() {
  mkdir -p "$CONFIG_DIR"
  (umask 077 && printf '%s' "$1" >"$2")
  chmod 600 "$2" 2>/dev/null || true
}

store_key() {
  local key="$1" store
  store="${DEEPFLOW_KEY_STORE:-auto}"

  if [[ "$store" == auto || "$store" == keychain ]]; then
    if [[ "$PLATFORM" == macos ]] && have security; then
      # security спрашивает пароль дважды (ввод + подтверждение) — подаём
      # его на stdin, чтобы ключ не оказался в списке процессов.
      if printf '%s\n%s\n' "$key" "$key" |
        security add-generic-password -U -s "$SERVICE" -a "$ACCOUNT" -w >/dev/null 2>&1; then
        rm -f "$KEY_FILE"
        echo "keychain (service=$SERVICE, account=$ACCOUNT)"
        return 0
      fi
      err "не удалось записать в Keychain, сохраняю в файл"
    fi
  fi

  if [[ "$store" == auto || "$store" == secret-service ]]; then
    if [[ "$PLATFORM" == linux ]] && have secret-tool; then
      if printf '%s' "$key" |
        secret-tool store --label='DeepFlow API key' service "$SERVICE" account "$ACCOUNT" >/dev/null 2>&1; then
        rm -f "$KEY_FILE"
        echo "secret-service (service=$SERVICE)"
        return 0
      fi
      err "secret-tool не смог сохранить ключ, сохраняю в файл"
    fi
  fi

  if [[ "$store" != auto && "$store" != file ]]; then
    err "хранилище '$store' недоступно на этой платформе — сохраняю в файл"
  fi
  write_file "$key" "$KEY_FILE"
  echo "file (mode 600): $KEY_FILE"
}

# ------------------------------------------------------------------ masking

mask() {
  local value="$1"
  if [[ ${#value} -le 8 ]]; then
    printf '***'
  else
    printf '%s…%s' "${value:0:4}" "${value: -4}"
  fi
}

# ----------------------------------------------------------------- commands

cmd_set() {
  [[ $# -eq 0 ]] || die "ключ не принимается аргументом (он виден в ps); используйте: printf '%s' '<key>' | df-auth.sh set"

  local key=""
  if [[ -t 0 ]]; then
    printf 'DeepFlow API key (dfk_...): ' >&2
    IFS= read -rs key || true
    printf '\n' >&2
  else
    key="$(cat)"
  fi
  key="$(printf '%s' "$key" | tr -d '\r\n')"
  [[ -n "$key" ]] || die "пустой ключ"
  case "$key" in
    *[[:space:]]*) die "ключ содержит пробелы/переводы строк" ;;
  esac
  if [[ ! "$key" =~ ^dfk_[A-Za-z0-9_-]{43}$ ]]; then
    err "предупреждение: ключ не похож на dfk_<43 символа>, сохраняю как есть"
  fi

  local where
  where="$(store_key "$key")"
  err "ключ сохранён: $where"
}

cmd_key() {
  local key
  key="$(resolve_key)" || die "ключ не настроен: попросите пользователя дать ключ и выполните df-auth.sh set"
  printf '%s' "$key"
}

cmd_url() {
  if [[ $# -eq 0 ]]; then
    resolve_url
    return 0
  fi
  local url="${1%/}"
  [[ "$url" =~ ^https?://[^[:space:]]+$ ]] || die "URL должен начинаться с http:// или https://"
  write_file "$url" "$URL_FILE"
  err "URL сохранён: $url ($URL_FILE)"
}

cmd_status() {
  local key source
  echo "URL:  $(resolve_url) [$(url_source)]"
  if key="$(resolve_key)"; then
    source="$(key_source)"
    echo "KEY:  настроен, $(mask "$key") [$source]"
    case "$source" in
      env:*) echo "      переменная окружения не сохраняется: для постоянного хранения выполните set" ;;
    esac
  else
    echo "KEY:  не настроен — попросите пользователя дать ключ и выполните set"
    return 1
  fi
}

cmd_test() {
  local url key base code
  url="$(resolve_url)"
  key="$(resolve_key)" || die "ключ не настроен — выполните set"
  base="${url%/}"
  [[ "$base" == */api/v1 ]] || base="$base/api/v1"
  code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --header "Authorization: Bearer $key" \
    --header 'Accept: application/json' \
    "$base/public/projects" 2>/dev/null || true)"
  case "$code" in
    200) echo "OK: HTTP 200 — ключ и URL рабочие ($url)" ;;
    401) err "HTTP 401 — ключ недействителен/отозван: попросите новый и повторите set"; exit 1 ;;
    403) err "HTTP 403 — ключу не хватает scope projects:read, проект вне списка ключа или тариф без API"; exit 1 ;;
    000|'') err "нет соединения с $url"; exit 1 ;;
    *) err "HTTP $code"; exit 1 ;;
  esac
}

cmd_rm() {
  if [[ "$PLATFORM" == macos ]] && have security; then
    security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1 || true
  fi
  if [[ "$PLATFORM" == linux ]] && have secret-tool; then
    secret-tool clear service "$SERVICE" account "$ACCOUNT" >/dev/null 2>&1 || true
  fi
  rm -f "$KEY_FILE"
  err "ключ удалён из хранилищ (env-переменные не затрагиваются)"
}

usage() {
  cat >&2 <<'EOF'
usage: df-auth.sh <command>

  set             сохранить ключ из stdin (printf '%s' '<key>' | df-auth.sh set)
  key             напечатать ключ (для df.sh)
  url [<url>]     показать или сохранить базовый URL
  status          состояние настройки (маска ключа)
  test            проверить ключ запросом GET /public/projects
  rm              удалить ключ из хранилищ
EOF
}

case "${1:-}" in
  set) cmd_set "${@:2}" ;;
  key) cmd_key ;;
  url) cmd_url "${@:2}" ;;
  status) cmd_status ;;
  test) cmd_test ;;
  rm) cmd_rm ;;
  help|-h|--help|"") usage; [[ -n "${1:-}" ]] || exit 1 ;;
  *) usage; exit 1 ;;
esac
