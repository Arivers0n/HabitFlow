#!/usr/bin/env bash
# Снимки экрана на симуляторе: проверяем, что экраны и анимации реально рисуются.
set -u
APP=com.ariverson.habitflow
OUT=shots
mkdir -p "$OUT"
shot() { sleep "$2"; xcrun simctl io booted screenshot --type=png "$OUT/$1.png" >/dev/null 2>&1 && echo "снимок $1"; }
launch() { xcrun simctl terminate booted $APP >/dev/null 2>&1; sleep 1; xcrun simctl launch booted $APP "$@" >/dev/null; }

xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 >/dev/null 2>&1 || true

launch;                                         shot 01-welcome 7
launch -hfShot egg;                             shot 02-today-egg 7
launch -hfShot egg -hfOpen companion;           shot 03-companion-egg 6
launch -hfShot egg -hfOpen debug/hatch
shot 04-hatch-1 3.0; shot 04-hatch-2 0.6; shot 04-hatch-3 0.4; shot 04-hatch-4 2.5
launch -hfShot stress;                          shot 05-today 7
launch -hfShot stress -hfOpen companion;        shot 06-companion 6
launch -hfShot stress -hfOpen progress;         shot 07-progress 6
launch -hfShot stress -hfOpen debug/resist;     shot 08-resist-1 2.4; shot 08-resist-2 1.6
launch -hfShot stress -hfOpen ai;               shot 09-ai 6
launch -hfShot stress -hfOpen friends;          shot 10-friends 6
launch -hfShot stress -hfOpen debug/chat;       shot 11-chat 6
launch -hfShot stress -hfShotCharacter robot -hfOpen debug/levelup; shot 12-levelup 4
launch -hfShot stress -hfOpen cards;            shot 13-cards 6
launch -hfShot stress -hfOpen settings/quickCards; shot 14-settings-cards 6
launch -hfShot stress -hfOpen settings/sounds;  shot 15-settings-sounds 6
launch -hfShot stress -hfOpen settings/health;  shot 16-settings-health 6
launch -hfShot stress -hfOpen settings/qa;      shot 17-settings-qa 6
launch -hfShot stress -hfOpen review;           shot 18-review 6
launch -hfShot stress -hfOpen relax;            shot 19-relax 6
# Конструктор виджетов: по снимку на размер (рабочий стол и экран блокировки)
launch -hfShot stress -hfWidgetFamily small -hfWidgetSlot 1 -hfOpen settings/widgets;           shot 20-widgets-small 6
launch -hfShot stress -hfWidgetFamily medium -hfWidgetSlot 2 -hfOpen settings/widgets;          shot 21-widgets-medium 6
launch -hfShot stress -hfWidgetFamily large -hfWidgetSlot 3 -hfOpen settings/widgets;           shot 22-widgets-large 6
launch -hfShot stress -hfWidgetFamily lockCircular -hfWidgetSlot 1 -hfOpen settings/widgets;    shot 23-widgets-lock-circular 6
launch -hfShot stress -hfWidgetFamily lockRectangular -hfWidgetSlot 1 -hfOpen settings/widgets; shot 24-widgets-lock-rect 6
launch -hfShot stress -hfWidgetFamily lockInline -hfWidgetSlot 1 -hfOpen settings/widgets;      shot 25-widgets-lock-inline 6
ls -1 "$OUT"
