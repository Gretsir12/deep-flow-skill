#!/usr/bin/env bash
# df.sh — обёртка над публичным API DeepFlow.
#
# Учётные данные берутся в таком порядке:
#   1) DEEPFLOW_API_URL / DEEPFLOW_API_KEY из окружения (CI, разовый запуск);
#   2) хранилище, которым управляет scripts/df-auth.sh:
#      Keychain (macOS), Secret Service (Linux), DPAPI (Windows через
#      df-auth.ps1), иначе файл 0600 в ~/.config/deepflow.
#
# Первичная настройка (ключ в чат и в argv не попадает):
#   printf '%s' '<dfk_...>' | scripts/df-auth.sh set
#   scripts/df-auth.sh url 'https://app.deepflow.example'
#   scripts/df-auth.sh test
#
# Использование:
#   df.sh <METHOD> <PATH> [JSON_BODY]
#
# Примеры:
#   df.sh GET  /public/projects
#   df.sh GET  /public/projects/1/services
#   df.sh POST /public/projects/1/services/2/deployments '{"commit_sha":"<40 hex>"}'
#
# Тело ответа печатается в stdout, HTTP-код — в stderr.
# Внимание: POST-деплой и откат требуют явного согласия пользователя.
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
auth="${self_dir}/df-auth.sh"

method="${1:?usage: df.sh <METHOD> <PATH> [JSON_BODY]}"
path="${2:?usage: df.sh <METHOD> <PATH> [JSON_BODY]}"
body="${3:-}"

api_url="${DEEPFLOW_API_URL:-}"
api_key="${DEEPFLOW_API_KEY:-}"

if [[ -z "$api_key" || -z "$api_url" ]] && [[ -f "$auth" ]]; then
  [[ -n "$api_url" ]] || api_url="$(bash "$auth" url 2>/dev/null || true)"
  [[ -n "$api_key" ]] || api_key="$(bash "$auth" key 2>/dev/null || true)"
fi

if [[ -z "$api_url" ]]; then
  echo "df.sh: DeepFlow API URL не настроен — выполните scripts/df-auth.sh url <url>" >&2
  exit 1
fi
if [[ -z "$api_key" ]]; then
  echo "df.sh: DeepFlow API key не настроен — попросите пользователя дать ключ и выполните scripts/df-auth.sh set" >&2
  exit 1
fi

base="${api_url%/}"
case "$base" in
  */api/v1) ;;
  *) base="${base}/api/v1" ;;
esac

# Path может быть как «/public/projects», так и «public/projects».
path="/${path#/}"
url="${base}${path}"

args=(
  --silent --show-error
  --request "$method"
  --header "Authorization: Bearer ${api_key}"
  --header "Accept: application/json"
  --write-out '\n%{http_code}'
)

if [[ -n "$body" ]]; then
  args+=(--header "Content-Type: application/json" --data "$body")
fi

# Ответ и код разделяем: код уходит в stderr, чтобы не ломать JSON в stdout.
response="$(curl "${args[@]}" "$url")" || {
  echo "df.sh: request failed: ${method} ${url}" >&2
  exit 1
}
code="${response##*$'\n'}"
payload="${response%$'\n'*}"

[[ -n "$payload" ]] && printf '%s\n' "$payload"
printf 'HTTP %s\n' "$code" >&2

case "$code" in
  2??) exit 0 ;;
  *) exit 1 ;;
esac
