---
name: go-engineer
description: Use when the task is Go code in txmlconnector-native — the pure-Go TRANSAQ client (native/...), the DLL-compatible XML connector native.Connector, commands/, the connector.Connector boundary and Win32 DLL adapter, the C ABI library cmd/connector, RE tools under tools/, tests or CI — and you need the repo-specific implementation and review cycle
type: prompt
whenToUse: When working on native/{wire,session,records,model,xmlcompat,cryptoprofile,replay,natsout}, native.Client/native.Connector, commands, connector, cmd/connector, tools/*, fixtures, Makefile or CI in txmlconnector-native
---

# Go-инженер в txmlconnector-native

**Назначение.** Маршрут Go-задачи от постановки до проверенного изменения в нативном клиенте TRANSAQ.
Скилл — надстройка над [AGENTS.md](../../../AGENTS.md), [README.md](../../../README.md) и
[docs/protocol](../../../docs/protocol), а не их замена.

gRPC-сервер, `client/`, терминал и Docker живут в
[github.com/kmlebedev/txmlconnector](https://github.com/kmlebedev/txmlconnector) — там свой
`go-engineer`. Здесь — то, что нужно переделывать при обновлении DLL
(runbook — [docs/dll-update.md](../../../docs/dll-update.md), скилл `.claude/skills/dll-update`).

## 1. Карта пакетов

| Пакет | Что | Инвариант |
|---|---|---|
| `native/wire` | кадры, упакованные целые, `W/L/G/Zn/D` | побайтно как DLL; таблица примитивов — tools/re/README.md RE-1 |
| `native/cryptoprofile` | ГОСТ-профиль, S-box | байты таблиц — из DLL (D), не «улучшать» |
| `native/session` | логин, RQ_*, recover/relogin, транзакции | `RQ_TRANSACT` не повторяется; неизвестный исход — `ErrOutcomeUnknown` |
| `native/records` | разбор записей RQ_MAIN по тегам | неизвестный тег → `UnknownRecords`, не паника |
| `native/model` | типизированные структуры | деньги/объёмы — `model.Decimal`; `float64` только где на проводе `D`; время — UTC |
| `native/xmlcompat` | XML как у DLL (`Render`) | единственное место XML; сверка `checkDLL` с `*-dll.xml` |
| `native` | `Client` (событийный `Run`), `Connector` (45 команд) | `connector.Connector`; команды — в `client_*.go`, декодеры — `events_*.go` |
| `commands` | XML-структуры команд/колбэков | контракт DLL; потребители — внешние клиенты |
| `connector` | интерфейс + Win32-адаптер DLL | Win32 — только `native_windows_amd64.go` под build tag |
| `cmd/connector` | C ABI drop-in (cgo) | 9 экспортов, тексты/коды как у DLL (C5) |
| `tools/*` | RE: прокси, проигрыватель, wire-decode, harness, soak, cabi | живые прогоны — под env, без секретов в выводе |

## 2. Цикл работы

1. Прочитай задачу, нужный `docs/protocol/*.md`, AGENTS.md §6 (red lines).
2. Ветка от `main` (или worktree); один логический change set.
3. **Сначала тест**: фикстура `testdata/<запись>-{live,inject}.hex[.gz]` + эталон `<запись>-dll.xml[.gz]`;
   тест падает по ожидаемой причине.
4. Реализуй по слоям: `wire` → `session`/`records` → `model` → `xmlcompat` → `native`.
5. `make verify` (gofmt, vet, build, кросс-сборки CGO_ENABLED=0, `go test -race ./...`).
6. Задокументируй факт в `docs/protocol/*` со статусом S/O/D/I.
7. Commit (Conventional Commits), в описании — команды и результаты; непроверенное помечено.

## 3. Go-правила

1. `native/...` — чистый Go, `CGO_ENABLED=0`, без новых зависимостей (кроме `golang.org/x/text`;
   NATS/protobuf — только `native/natsout`, `proto/`, `tools/`). cgo — только `cmd/connector`.
2. Никаких `float64` для цен и денег; `time.Time` в UTC.
3. Ошибки оборачиваются `%w`; библиотека не вызывает `log.Fatal` и не печатает секреты.
4. Конкурентность: один владелец сессии; `-race` обязателен; отмена через `context`.
5. Тесты не ходят в сеть и не требуют DLL/Wine; живые — под `TC_*`/`TXML_DEMO_*` и `t.Skip`.
6. Generated `*.pb.go` — только `make compile`.
7. Win32 API — только в `connector/native_windows_amd64.go`; для остальных платформ —
   `native_unsupported.go` с явной ошибкой.

## 4. Команды

| Цель | Команда |
|---|---|
| Всё перед commit | `make verify` |
| Кросс-сборки | `make cross` |
| Окружение RE | `make re-check` / `make re-check-full` |
| C ABI | `make cabi`, `make cabi-test`, `make cabi-conformance` (нужен C-компилятор) |
| Протокол на Python | `make re-selftest` |
| Proto | `make compile` |

В песочнице DSH глобальный кэш Go недоступен: `make` сам ставит `GOCACHE=$PWD/.cache/go-build`.

## 5. Ревью-чек-лист

- [ ] Diff соответствует задаче; нет попутных рефакторингов и новых зависимостей.
- [ ] Побайтное совпадение с DLL доказано фикстурой/оракулом, а не «по документации».
- [ ] `Decimal`/UTC; нет `float64` для денег.
- [ ] `ErrOutcomeUnknown` для транзакций с неизвестным исходом; автоповтора нет.
- [ ] Неизвестные записи/теги не роняют сессию.
- [ ] Фикстуры обезличены; секретов нет в коде, логах, тестах, коммитах.
- [ ] `docs/protocol/*` обновлён со статусами; `coverage.md` — если изменилось покрытие.
- [ ] Непроверенное на Windows/Wine/демо явно помечено.
