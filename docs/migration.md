# Выделение txmlconnector-native из txmlconnector

Дата: 2026-11-10. Источник: `github.com/kmlebedev/txmlconnector`, `main` `61b6289` (PR #72).
Цель: `github.com/kmlebedev/txmlconnector-native` (публичный; на старте — `Initial commit` с LICENSE MIT).

## Что перенесено (с историей)

История перенесённых путей сохранена `git filter-repo --path … --path-rename client/commands/:commands/`
(авторы и даты сохранены; рабочий email автора заменён на `…@users.noreply.github.com`, как и в
истории `origin/main` txmlconnector) и слита с `Initial commit` нового репозитория
(`--allow-unrelated-histories`). Изменения, вошедшие в `origin/main` после снимка (`0312bf3` — только
`docs/protocol/alltrades.md`, `765bac3` SecuritiesAdded), перенесены `git am` с исходным авторством;
содержимое перенесённых путей сверено с `61b6289` (`diff -r` после замены import-путей). Теги исходного репозитория (`v0.0x`, `compat-v1.0.0*`) не перенесены:
у нового модуля своя линейка версий.

| Было (txmlconnector) | Стало |
|---|---|
| `native/**` | `native/**` |
| `client/commands` | `commands` |
| `connector/` (интерфейс + Win32-адаптер DLL) | `connector/` |
| `proto/marketdata` | `proto/marketdata` (`go_package` обновлён, перегенерирован `protoc`) |
| `cmd/connector` (C ABI) | `cmd/connector` |
| `tools/{re,cabi,tcproxy,replay-server,wire-decode,reference-harness,native-login,native-soak,native-trades}` | то же |
| `docs/{protocol,deepseek,research}`, `docs/{COMPATIBILITY,ROADMAP-GO,TRANSAQ-SERVER-RESEARCH}.md`, `docs/superpowers/plans/2026-11-04-native-transaq-client.md` | то же |
| `.kimi-code/skills/go-engineer` | переписан под этот репозиторий (в txmlconnector остаётся свой) |
| `txmlconnector64-6.47.2.26.4.dll` | то же (в txmlconnector тоже остаётся: DLL-backend сервера и релизы) |
| `.github/workflows/compat-release.yml` | то же |

Новое в этом репозитории: `go.mod` (`module github.com/kmlebedev/txmlconnector-native`), `Makefile`,
`.github/workflows/go-test.yml`, `AGENTS.md`/`CLAUDE.md`, `README.md`, runbook
[`docs/dll-update.md`](dll-update.md), скиллы `.claude/skills/dll-update` и
`.claude/skills/reverse-engineering` (Apache-2.0, ранее лежал локально вне git).

## Что осталось в txmlconnector

`server/` (gRPC, `TC_BACKEND=dll|native`), `client/` (gRPC-клиент), `proto/connect*`, `terminal/`,
`cmd/terminal`, `cmd/md-recorder`, `examples/`, `docker/`, `deploy/`, `skills/`, `docs/ai-terminal/`.
Они импортируют `github.com/kmlebedev/txmlconnector-native/{native,commands,connector}`.
Для совместимости внешних потребителей `client/commands` и `connector` в txmlconnector оставлены
тонкими алиасами на пакеты этого модуля (deprecated).

## Исторические документы

`docs/deepseek/*`, `docs/superpowers/plans/*`, `docs/ROADMAP-GO.md` описывают работу, когда код жил в
txmlconnector: пути `client/commands`, ветки `plan/native-client`, PR `#47…#50` относятся к
`kmlebedev/txmlconnector`. Они не переписывались, чтобы не терять соответствие истории коммитов.
