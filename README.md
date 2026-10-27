# CoreDataMapping

Swift Package з універсальними Core Data helpers для явного DTO → Entity mapping.
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

DTO, Core Data model, Entity subclasses, `CoreDataStack`, feature mappers і
repositories визначає застосунок.

`Tests/CoreDataMappingTests/Example` містить перенесений приклад застосунку лише
як test support. Він компілюється разом із тестами й не входить у library product.
Тести створюють DTO в коді, а короткі JSON-зразки перевіряють тільки контракти
декодування. Великі серверні відповіді не потрібні для `swift test`.

- [Практичний посібник](CORE_GUIDE.md): API, identity, relationships, ownership,
  delete rules і складені ключі.
- [Архітектура](ARCHITECTURE.md): контракти, context queue, batches, cancellation
  та межі відповідальності пакета.
- [Тестування](TESTING.md): структура test target, зв’язки й стратегія фікстур.
- [AGENTS.md](AGENTS.md): інструкції для Codex під час роботи над пакетом.

Підключіть package product `CoreDataMapping` до застосунку через Swift Package
Manager і імпортуйте модуль у файлах із маперами та repositories.

Для перевірки пакета на macOS запустіть `swift test`. Після зміни тестової
`.xcdatamodeld` виконайте `Scripts/update-test-model.sh` і додайте оновлену
`.momd` до тієї самої зміни.
