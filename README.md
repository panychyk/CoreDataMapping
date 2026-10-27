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

`Tests/CoreDataMappingTests/MedicalCongress` містить тестову систему медичних
конгресів: модель `MedicalCongressModel.xcdatamodeld`, класи в `Entities`,
сценарії в `Suites` і код запису графа. Кожен suite об’єднує кілька незалежних
тестів одного потоку. Тести використовують `NSInMemoryStoreType` та перевіряють спільні й
дочірні зв’язки, кілька імпортів, rollback і cancellation. Тестова схема не
входить у library product.

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
