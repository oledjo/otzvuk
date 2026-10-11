# ERRORS

## Сборка в папке «Документы» (iCloud)
**What didn't work:** `xcodebuild ... -derivedDataPath build` внутри папки проекта: `CodeSign failed: resource fork, Finder information, or similar detritus not allowed`.
**What worked:** `-derivedDataPath` вне синхронизируемой папки (например, `/private/tmp/...`).
**Note for next time:** при подобной ошибке сначала выносить DerivedData за пределы iCloud-папок.

## Запись в симуляторе
**What didn't work:** тап по кнопке записи сразу после запуска попадал в приложение до его появления; активация записи занимает несколько секунд в симуляторе.
**What worked:** подождать загрузки приложения; на реальном устройстве задержки нет (не проверено).
