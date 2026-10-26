#!/usr/bin/env python3
"""Собирает install-habitflow.sh: один файл со всеми хуками внутри (base64)."""
import base64, pathlib
root = pathlib.Path(__file__).parent
files = [("pb_hooks", p) for p in sorted((root / "pb_hooks").glob("*.js"))] + \
        [("pb_migrations", p) for p in sorted((root / "pb_migrations").glob("*.js"))]
parts = []
for folder, p in files:
    b = base64.encodebytes(p.read_bytes()).decode()
    parts.append(f'base64 -d > "$DIR/{folder}/{p.name}" <<\'B64\'\n{b}B64\n')
script = '''#!/usr/bin/env bash
# Модуль HabitFlow для сервера Копилки: синхронизация привычек и круги друзей.
# Запуск на VPS: sudo bash install-habitflow.sh
# Аккаунты, вход через Google/Яндекс/Apple и ИИ остаются общими с Копилкой. Данные Копилки не меняются.
set -euo pipefail
DIR=/opt/kopilka
say() { printf '\\n\\033[1;36m%s\\033[0m\\n' "$1"; }
die() { printf '\\n\\033[1;31mОшибка: %s\\033[0m\\n' "$1"; exit 1; }
[ "$(id -u)" -eq 0 ] || die "запустите через sudo"
[ -x "$DIR/pocketbase" ] || die "сервер Копилки не найден в $DIR — сначала установите его (install.sh из репозитория Копилки)"
PORT=$(grep -o -- '--http=127.0.0.1:[0-9]*' /etc/systemd/system/kopilka.service | grep -o '[0-9]*$' || echo 8090)

say "Сохраняю резервную копию базы"
mkdir -p "$DIR/backups"
if command -v sqlite3 >/dev/null; then
  sqlite3 "$DIR/pb_data/data.db" ".backup '$DIR/backups/before-habitflow-$(date +%F-%H%M).db'" || true
fi

say "Устанавливаю модуль HabitFlow"
mkdir -p "$DIR/pb_hooks" "$DIR/pb_migrations"
''' + "".join(parts) + '''
chown -R kopilka:kopilka "$DIR/pb_hooks" "$DIR/pb_migrations"

say "Перезапускаю сервер"
systemctl restart kopilka
for i in $(seq 1 20); do
  sleep 1
  if curl -fsS "http://127.0.0.1:$PORT/api/hf/ping" 2>/dev/null | grep -q habitflow; then
    URL=$(cat "$DIR/url" 2>/dev/null || echo "")
    say "Готово! HabitFlow подключён${URL:+ к $URL}."
    echo "Копилка работает как раньше: $(curl -fsS "http://127.0.0.1:$PORT/api/kp/ping" >/dev/null && echo да || echo 'проверьте: journalctl -u kopilka -n 50')"
    exit 0
  fi
done
die "модуль не отвечает. Логи: journalctl -u kopilka -n 80"
'''
out = root / "install-habitflow.sh"
out.write_text(script)
out.chmod(0o755)
print(out, len(script), "байт")
