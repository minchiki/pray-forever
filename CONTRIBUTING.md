# Как помочь проекту

Спасибо, что хотите помочь. Ниже — как устроен проект и что проверить перед pull request.

## Сообщить об ошибке или предложить идею

Откройте [issue](https://github.com/minchiki/pray-forever/issues/new/choose) по шаблону. Для ошибки укажите платформу и версию системы, модель телефона, версию приложения и шаги, после которых она появляется. Если будильник не зазвонил, приложите время намаза, задержку и метод расчёта из настроек.

Об уязвимостях пишите не в issue, а по [SECURITY.md](SECURITY.md).

## Как устроен код

Приложение нативное на двух платформах, и поведение у них одинаковое.

- Логика (`Sajda/Services`, `Sajda/Recitation`, `Sajda/Pause` и `android/app/src/main/java/com/prayforever/app/core`) — чистые функции без UI. Меняете правило на одной платформе — меняйте и на другой, вместе с тестами: тест-кейсы у них общие.
- Звуки, шрифт и переводы лежат в `Sajda/Resources` и общие: Android берёт их оттуда при сборке. Новую строку добавляйте в оба `Localizable.strings` (`ru` и `en`). Строки только для Android — в `android/app/src/main/res/values*/strings.xml`.
- Тексты сур — в `Sajda/Recitation/Surah.swift`. После правки выполните `python scripts/gen_android_surahs.py`; тест `SurahTest.surahTextsMatchIosSource` не даст им разойтись.
- Иконки и баннеры генерируются скриптами в `design/`, не редактируйте PNG вручную.

## Перед pull request

Android:

```bash
cd android
./gradlew spotlessApply                                  # формат (ktlint)
./gradlew spotlessCheck lintDebug testDebugUnitTest assembleDebug
```

iOS (на Mac):

```bash
swiftlint
xcodegen generate
xcodebuild test -project Sajda.xcodeproj -scheme Sajda -destination 'platform=iOS Simulator,name=iPhone 16'
```

CI запускает то же самое на каждом pull request.

Если изменение касается будильника, проверьте его вручную: «Настройки → Проверить будильник», а для Android ещё и сценарий с выгруженным приложением и выключенным экраном.

## Коммиты

Сообщения — в стиле [Conventional Commits](https://www.conventionalcommits.org/ru/v1.0.0/): `feat:`, `fix:`, `docs:`, `build:`, `ci:`, `chore:`, `test:`, `refactor:`. Для изменений одной платформы можно указать область: `feat(android): …`. Заметные изменения добавляйте в раздел `Unreleased` файла [CHANGELOG.md](CHANGELOG.md).

## Принципы

- Распознавание остаётся на устройстве. Сетевые сервисы и аналитику не добавляем.
- Будильник нельзя сделать проще выключить без испытания: такие изменения обсуждаем в issue заранее.
- Разрешения — только необходимые.

Участвуя в проекте, вы соглашаетесь с [правилами поведения](CODE_OF_CONDUCT.md).
