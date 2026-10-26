#!/usr/bin/env bash
# Снимки экрана на симуляторе: проверяем, что экраны и анимации реально рисуются.
set -u
APP=com.ariverson.habitflow
OUT=shots
mkdir -p "$OUT"
shot() { sleep "$2"; xcrun simctl io booted screenshot --type=png "$OUT/$1.png" >/dev/null 2>&1 && echo "снимок $1"; }
launch() { xcrun simctl terminate booted $APP >/dev/null 2>&1; sleep 1; xcrun simctl launch booted $APP "$@" >/dev/null; }
url() { xcrun simctl openurl booted "$1"; }

xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 >/dev/null 2>&1 || true

# 1. Первый запуск: приветствие и вход
launch
shot 01-welcome 7

# 2. Напарник в яйце
launch -hfShot egg
shot 02-today-egg 7
url habitflow://companion
shot 03-companion-egg 4
url habitflow://debug/hatch
shot 04-hatch-1 1.2
shot 04-hatch-2 0.5
shot 04-hatch-3 0.35
shot 04-hatch-4 2.5

# 3. Взрослый напарник и худшие данные
launch -hfShot stress
shot 05-today 7
url habitflow://companion
shot 06-companion 4
url habitflow://progress
shot 07-progress 4
url habitflow://debug/resist
shot 08-resist-1 0.9
shot 08-resist-2 1.6
launch -hfShot stress
url habitflow://ai
shot 09-ai 4
launch -hfShot stress
url habitflow://friends
shot 10-friends 5
launch -hfShot stress
url habitflow://debug/chat
shot 11-chat 5
launch -hfShot stress -hfShotCharacter robot
url habitflow://debug/levelup
shot 12-levelup 2.5

# 4. iPad-раскладка не снимаем: отдельный симулятор, слишком долго для каждого пуша
ls -1 "$OUT"
