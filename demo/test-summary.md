# Результаты проверок

Дата: 18 ноября 2026 г. Среда: macOS 27.2.1, Apple Silicon, Xcode 27.2 (27B52), SDK iOS Simulator 27.2, Go 1.27.4. Стенд: синтетические данные, без подключённого контроллера.

| Где запускалось | Команда | Результат |
|---|---|---|
| Корень приложения | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 9 тестов XCTest прошли, 0 ошибок |
| Корень приложения | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project cncapp.xcodeproj -scheme cncapp -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/cncapp-architecture-ios-build CODE_SIGNING_ALLOWED=NO build -quiet` | Сборка для iOS Simulator завершилась успешно |
| Корень сервера `cnc_machine` | `go test ./internal/transport/rest -run TestPreviewAvailableToOtherClientsWithoutController -count=1 -v` | Серверный тест загрузки и предпросмотра без контроллера прошёл |

Тесты клиента охватывают блокировку действий при переподключении, ограничение числа повторов, условия запуска и загрузки, координаты и совместимость с JSON без необязательных полей. Сборка для симулятора подтверждает компиляцию приложения. Ручная приёмка, снимки и работа с оборудованием в этой проверке не выполнялись.
