# Проверки истории Sleepring 1

`python3 tool/test_ios_history.py` компилирует реальные методы чтения/автоматической
очистки и `Completer` на macOS с Combine. SDK IO и модели заменены doubles, timeout
во временной сборке равен 40 мс. Проверяются 23 сценария чтения, завершения и очистки.
Нужен `swiftc` из Xcode Command Line Tools.

`python3 tool/test_android_history.py` извлекает реальные методы YuchengCore,
YuchengApiImpl, YuchengBleService и методы HTTP-репозитория. JVM doubles заменяют Android,
BLE, данные конвертеров и HTTP-транспорт. 37 сценариев проверяют независимость категорий,
null/error, timeout, cancellation, поздние callbacks и защиту SDK delete. Нужен JDK
(`JAVA_HOME`, по умолчанию Android Studio JBR) и уже скачанные в Gradle cache Kotlin
2.4.10, coroutines 1.9.0, kotlin-reflect 1.9.24 и annotations 23.0.0. Скрипт ничего
не скачивает, не меняет Gradle-конфиг, pub cache или исходный checkout.

Базовый код 904ba79: iOS 9/23, Android 6/24. Исправленный код: iOS 23/23,
Android расширен до 37/37. Полный iOS typecheck с реальными SDK прошёл; standalone
Android Gradle compile остановился до Kotlin-компиляции на существующем
`build.gradle:45` (`kotlinOptions()` в AGP 9.0.1). Это не заменяет сборку на телефоне.

Автоматическая очистка после неполного чтения заблокирована до перезапуска процесса.
Следующий полный read не снимает запрет: API не передаёт token пары read/ack,
и поздний ack предыдущей попытки иначе мог бы стереть непрочитанную историю.
Явные deleteAllData/factory reset сохраняют отдельный контракт.

Android SDK 4.0.9 проверен через `javap -c -p`:
`YCBTClientImpl.packetHealthHandle` возвращает `(code=0, ratio=0f, null)` также при
ошибке CRC. Поэтому null нельзя считать подтверждённой пустотой, а ratio=100
нельзя использовать для завершения истории. Успешный пустой payload - `data: []`.
