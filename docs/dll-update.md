# Обновление под новую версию `txmlconnector64.dll`

Runbook для агента или разработчика, который получил новую сборку вендорской DLL
(`txmlconnector64-<ver>.dll`) и должен довести `native/`, C ABI-библиотеку (`cmd/connector`),
фикстуры и документацию протокола до совместимости с ней.

Текущий эталон: **`txmlconnector64-6.47.2.26.4.dll`**, SHA-256
`a197e2625e53c0df453687ae1b20ef2ae1a05e034cd20c424a7014b0c9726342`.

Принципы — те же, что в [AGENTS.md](../AGENTS.md) §6: **DLL — эталон**; каждое утверждение о протоколе —
со статусом **S** (демо-сервер) / **O** (оракул DLL) / **D** (декомпилятор) / **I** (вывод) и координатами
(адрес функции, фикстура, команда); оракул догадками не подменять; секреты и номера счетов не попадают
в git; торговые команды живьём — только по явному согласию пользователя в чате.

Процедуры RE-1…RE-4 — [tools/re/README.md](../tools/re/README.md); общая методика —
скилл [.claude/skills/reverse-engineering](../.claude/skills/reverse-engineering/SKILL.md).

---

## 0. Подготовка (ветка `dll/<ver>`)

```bash
git switch -c dll/<ver> main
cp /path/to/txmlconnector64-<ver>.dll .        # старую DLL пока не удалять: нужна для диффа
shasum -a 256 txmlconnector64-<ver>.dll
tools/re/check_env.sh                            # Ghidra/Wine/секреты/Go: PASS/WARN/FAIL
```

## 1. Триаж: насколько всё поменялось

| Шаг | Команда | Что сравнить |
|---|---|---|
| PE-инвентарь | `make dll-inventory TXC_VERSION=<ver>` | `docs/research/binary-inventory-<ver>.json` против `…-6.47.2.26.4.json`: секции, image base, timestamp, `anchors` (строки и их VA) |
| Экспорты | `make dll-exports TXC_VERSION=<ver>` | 9 экспортов и ординалы 1–9 (C ABI-контракт `cmd/connector`, `docs/protocol/cabi.md`) |
| Версия | `TXC_DLL=$PWD/txmlconnector64-<ver>.dll tools/re/run_dll.sh 1s '<command id="get_connector_version"/>'` | `<connector_version>` |
| Строки | `strings -el`/`strings` по обеим DLL, `diff` | новые/исчезнувшие XML-теги, `RQ_*`, тексты ошибок |

Итог триажа (новые экспорты, сдвиг адресов, новые теги/команды) записать в
`docs/protocol/dll-<ver>.md` до правок кода.

## 2. RE-1: перенос карт на новый бинарь

Адреса `FUN_18…` из `docs/protocol/*` и комментариев Go привязаны к 6.47.2.26.4. Для новой DLL:

1. Импорт в Ghidra (`${TMPDIR:-/tmp}/txc-ghproj-<ver>`, ~4 мин; обход песочницы — AGENTS.md §4).
2. Найти опорные функции по **строкам**, а не по адресам: `StrRefs.java` / `XrefDecomp.java 0 "s:<строка>"`.
   Опоры: таблица команд (было `FUN_1801774b0`), диспетчер тегов RQ_MAIN (`FUN_18038d7d0`),
   построитель запросов (`FUN_180355d50`), логин (`FUN_1803895c0`), криптопрофиль (S-box, VA
   `0x1809bea50`), примитивы чтения/записи потока (таблица в tools/re/README.md RE-1).
   При необходимости — BinDiff/Diaphora, см. `.claude/skills/reverse-engineering/references/diffing.md`.
3. Снять карты заново и сравнить с текущими:

   ```bash
   python3 tools/re/py/dll_maps.py commands /tmp/cmdtable-<ver>.c   # команды и needsConn
   python3 tools/re/py/dll_maps.py tags /tmp/dispatch-<ver>.c       # теги RQ_MAIN → обработчик
   G CallArgs.java /tmp/rq-<ver>.txt <адрес построителя>            # типы запросов RQ_*
   ```

4. Дифф карт → список изменений: новые/удалённые команды, теги, типы запросов, изменённые форматы
   полей записей (`W/L/G/Zn/D`, хвостовые необязательные поля).

## 3. Где в коде живёт привязка к версии

| Место | Что проверить/обновить |
|---|---|
| `native/connector.go` — `DefaultVersion`, `dllCommands` | версия `<ver>-native`; список команд и признак «нужно соединение» (тест `connector_matrix_test.go`) |
| `native/session/login.go`, `native/session/*` | константы `RQ_*`, формат логина/восстановления, версия клиента в запросе |
| `native/cryptoprofile/{gost,tables}.go` | S-box и параметры криптопрофиля (сравнить байты таблиц) |
| `native/records/*` | форматы записей и теги; новые теги → `UnknownRecords` в soak |
| `native/xmlcompat/*` | XML-рендер: порядок/имена тегов, тексты ошибок (`connector_errortexts_test.go`) |
| `commands/` | XML-структуры команд и колбэков (новые поля/теги) |
| `cmd/connector/main.go` `defaultVersion`, `include/txmlconnector.h`, `testdata/cabi-reference.json`, `testdata/cabi_scenarios.json` | C ABI: экспорты, тексты/коды обёртки (C5-конформанс) |
| `cmd/connector/internal/dlllog` | формат лог-файлов DLL |
| `tools/re/{run_dll.sh,check_env.sh,demo.env.example}`, `tools/cabi/zig_build.sh`, `Makefile` `TXC_VERSION`, `.github/workflows/*` | имя файла DLL, SHA-256, `TXC_VERSION` |
| `docs/protocol/*.md`, `docs/COMPATIBILITY.md` | адреса функций, статусы S/O/D/I |

`grep -rn '6\.47\.2\.26\.4' --exclude-dir=.git .` — полный список упоминаний версии.

## 4. Фикстуры и оракул (RE-2/RE-3)

1. Прогнать существующие тесты против новой DLL **оракулом**: каждая фикстура
   `native/records/testdata/<запись>-{live,inject}.hex[.gz]` проигрывается в новую DLL
   (`tools/replay-server`, RE-3), её XML сравнивается с `<запись>-dll.xml[.gz]`.
2. Расхождение XML → новая эталонная `-dll.xml` (коммит с пометкой `<ver>`) **и** правка Go до
   совпадения (`checkDLL`/`xmlcompat.Render`). Старую эталонную не перезаписывать молча: если
   поведение 6.47 нужно поддерживать, заводится версионированный профиль.
3. Новые записи/теги — RE-2 живой захват (`tools/tcproxy`, нужен `TC_PASSWORD` из `~/re/demo.env`),
   затем RE-3. Фикстуры обезличивать: `TESTCLIENT` / `TESTUNION` / `TESTLOGIN`, длины сохранять.
4. C ABI: `make cabi-conformance` с новой DLL как эталоном; при изменении текстов обёртки —
   обновить `cabi-reference.json`/`cabi_scenarios.json` (RE-3, только локальные сценарии).

## 5. RE-4: живая проверка

С согласия пользователя, в окне демо-сервера (09:50–23:50 МСК, будни):

```bash
set -a; . ~/re/demo.env; set +a
go run ./tools/native-login -addr "$TC_HOST:$TC_PORT"   # логин и загрузка каталога
TC_SOAK=1 go run ./tools/native-soak                  # read-only soak: UnknownRecords == 0, RSS стабилен (TC_SOAK_* — см. main.go)
go run ./tools/reference-harness -backend native '<command id="connect">…</command>' sleep:20s
```

Торговые команды (`neworder`, `cancelorder`, …) — только отдельным согласием, демо-счёт,
минимальный лот, цена далеко от рынка, отмена сразу.

## 6. Закрытие

- [ ] `make verify` зелёный; `go test -race ./...` без сети и DLL.
- [ ] Новая DLL в корне, старая удалена (или сохранена, если поддерживаются обе версии — решение
      владельца); SHA-256 обновлён в `.github/workflows/go-test.yml`, AGENTS.md, этом файле.
- [ ] `docs/protocol/dll-<ver>.md` — что изменилось, статусы S/O/D/I; `docs/protocol/coverage.md`
      пересчитан; `docs/COMPATIBILITY.md` §2 — новый эталон.
- [ ] Релиз C ABI: тег `compat-v*` (workflow `compat-release.yml`, `TXC_VERSION` в env).
- [ ] Потребители (`github.com/kmlebedev/txmlconnector`: `server`, `terminal`) обновлены на новую
      версию модуля отдельным PR в их репозитории.
