# CoreDataMapping

Swift Package для запису, читання та узгодження великих пов’язаних графів Core Data.
Пакет надає `CoreDataEntityIdentity`, `CoreDataStorage` і `CoreDataImporter`.
Потрібні iOS 18 або macOS 15 і новіші версії.

Застосунок створює та завантажує `NSPersistentContainer`, потім передає
importer-у private context, підключений до store coordinator:

```swift
import CoreDataMapping

let context = container.newBackgroundContext()
let importer = CoreDataImporter(context: context)

try await importer.write(dtos) { batch, storage in
    // Пакетно підготуйте Entity й з'єднайте граф у цьому context.
}
```

Модель Core Data, `NSManagedObject` subclasses і правила побудови графа визначає
споживач пакета.

`Tests/CoreDataMappingTests/Resources/GraphModel.xcdatamodeld` містить модель із
п’ятьма незалежними root Entity. Їхні `NSManagedObject` класи та код запису — у
`Fixtures`; `CoreDataTestStack.swift` завантажує `.momd` і створює in-memory або
SQLite store. Три тестові файли
перевіряють зв’язки, великі й паралельні імпорти, SQLite, міграцію, rollback,
cancellation, дублікати та осиротілі owned-записи. Тестова схема не входить у
library product.

- [Практичний посібник](CORE_GUIDE.md): API, identity, relationships, ownership,
  delete rules і складені ключі.
- [Архітектура](ARCHITECTURE.md): контракти, context queue, batches, cancellation
  та межі відповідальності пакета.
- [Тестування](TESTING.md): структура test target, зв’язки й стратегія фікстур.
- [AGENTS.md](AGENTS.md): інструкції для Codex під час роботи над пакетом.

Підключіть package product `CoreDataMapping` до застосунку через Swift Package
Manager і імпортуйте модуль у коді, який записує та читає граф Core Data.

Для перевірки пакета на macOS запустіть `swift build` і `swift test`.
Після зміни `.xcdatamodeld` виконайте `Scripts/update-test-model.sh` і збережіть
оновлену `.momd` разом із нею.
