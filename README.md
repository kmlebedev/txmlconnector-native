# txmlconnector-native

Чистый Go-клиент торгового сервера TRANSAQ (Finam), восстановленный по вендорской
`txmlconnector64-6.47.2.26.4.dll`, и всё, что нужно, чтобы держать его совместимым с новыми
версиями DLL: документация протокола, RE-инструменты, фикстуры, оракул и скиллы агентов.

- **`native.Client`** — типизированный клиент без DLL, Wine и XML: логин, каталог, подписки,
  история/тики, заявки и стопы, позиции/лимиты/портфели, новости, опционы, РПС/РЕПО.
- **`native.Connector`** — XML-коннектор поверх `native.Client`: 45/45 команд TXmlConnector,
  XML колбэков побайтно как у DLL (`connector.Connector`).
- **`cmd/connector`** — C ABI drop-in: `libtxmlconnector.so` / `.dylib` / `txmlconnector64.dll`
  с 9 экспортами оригинальной DLL.
- **`tools/`, `docs/protocol/`** — восстановленный протокол (статусы S/O/D/I), процедуры RE-1…RE-4,
  runbook обновления DLL.

Репозиторий выделен из [kmlebedev/txmlconnector](https://github.com/kmlebedev/txmlconnector)
2026-11-10 с сохранением истории (см. [docs/migration.md](docs/migration.md)). gRPC-сервер,
gRPC-клиент, AI-терминал и Docker-образы остались там и импортируют этот модуль.

## Установка

```bash
go get github.com/kmlebedev/txmlconnector-native@latest
```

## Нативный клиент

```go
import (
    "github.com/kmlebedev/txmlconnector-native/native"
    "github.com/kmlebedev/txmlconnector-native/native/model"
)

ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
defer cancel()

client, err := native.Dial(ctx, native.ClientConfig{
    Address:  "tr1-demo5.finam.ru:3939",
    Login:    os.Getenv("TC_LOGIN"),
    Password: os.Getenv("TC_PASSWORD"),
})
if err != nil {
    log.Fatal(err)
}
defer client.Close()

sber := model.Symbol{Board: "TQBR", SecCode: "SBER"}
if err := client.Subscribe(ctx, native.Subscription{
    AllTrades:  []model.Symbol{sber},
    Quotations: []model.Symbol{sber},
}); err != nil {
    log.Fatal(err)
}
err = client.Run(ctx, native.RunOptions{RqDelay: 100 * time.Millisecond}, func(events []model.Event) error {
    for _, ev := range events {
        switch e := ev.(type) {
        case *model.Trade:
            log.Printf("trade %s:%s %s x %d", e.Board, e.SecCode, e.Price, e.Quantity)
        case *model.Quotation:
            log.Printf("quotation %s:%s %+v", e.Symbol.Board, e.Symbol.SecCode, e.Fields)
        case model.ServerStatus:
            log.Printf("server connected=%v recover=%v", e.Connected, e.Recover)
        }
    }
    return nil
})
```

XML-клиенты, написанные под DLL, используют `native.Connector` (тот же `connector.Connector`, что и
Win32-адаптер `connector.New`), а XML-структуры команд и колбэков — пакет `commands`.

## Состав

| Путь | Что |
|---|---|
| `native/` | `Client`, `Connector`, `wire`, `session`, `records`, `model`, `xmlcompat`, `cryptoprofile`, `replay`, `natsout`, `testserver` |
| `commands/` | XML-структуры команд и колбэков TXmlConnector |
| `connector/` | интерфейс `connector.Connector` и Win32-адаптер вендорской DLL (`windows/amd64`) |
| `cmd/connector/` | C ABI drop-in библиотека (cgo), header `include/txmlconnector.h` |
| `proto/marketdata/` | protobuf ленты сделок для `native/natsout` |
| `tools/re/` | RE-1…RE-4: Ghidra-скрипты, Python-модель протокола, прокси/оракул, `run_dll.sh`, `check_env.sh` |
| `tools/{tcproxy,replay-server,wire-decode,reference-harness}` | захват, проигрывание, декодирование, сравнение DLL ↔ native |
| `tools/{native-login,native-soak,native-trades}` | живые проверки (env-gated, read-only) |
| `tools/cabi/` | Zig-сборка C ABI и нормализатор PE (`pe-repro`) |
| `docs/protocol/` | восстановленный протокол, статусы S/O/D/I, `coverage.md` |
| `docs/dll-update.md` | **runbook обновления под новую DLL** |
| `docs/COMPATIBILITY.md`, `docs/ROADMAP-GO.md`, `docs/TRANSAQ-SERVER-RESEARCH.md`, `docs/research/` | совместимость, дорожная карта, исследование бинаря |
| `docs/deepseek/`, `docs/superpowers/plans/` | рабочие материалы команды агентов и план реализации (исторические) |
| `.claude/skills/`, `.kimi-code/skills/` | скиллы агентов: `dll-update`, `reverse-engineering`, `go-engineer` |
| `txmlconnector64-6.47.2.26.4.dll` | эталонная вендорская DLL (SHA-256 `a197e262…9726342`), не модифицируется |

## Сборка и проверки

```bash
make verify            # gofmt, vet, build, кросс-сборки CGO_ENABLED=0, go test -race ./...
make re-check          # готовность окружения RE (Ghidra/Wine/секреты), секреты не печатает
make cabi cabi-test    # C ABI на текущей ОС (нужен C-компилятор)
make cabi-conformance  # C5: сценарии против эталонной DLL
make help              # все цели
```

Релизы C ABI собирает [`.github/workflows/compat-release.yml`](.github/workflows/compat-release.yml)
на тег `compat-v*` (linux amd64/arm64, windows amd64, macOS arm64/amd64 + `SHA256SUMS`).

## Обновление DLL

Новая версия `txmlconnector64.dll` → [docs/dll-update.md](docs/dll-update.md) (скилл
`.claude/skills/dll-update`): триаж бинаря, перенос карт Ghidra, оракул по фикстурам, правка
`native/`, живая проверка, релиз.

## Безопасность

Логин и пароль — только из окружения (`TC_LOGIN`, `TC_PASSWORD`; для RE — `~/re/demo.env` вне
репозитория). Фикстуры обезличены. Торговые команды против живого сервера — только осознанно, на
демо-счёте.
