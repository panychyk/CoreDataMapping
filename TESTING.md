# Тести зберігання графів

## Структура

`Tests/CoreDataMappingTests` розділяє сценарії за контрактом, має явний стек і `Fixtures`:

- `GraphLifecycleTests.swift` — повні snapshots, повторний запис, SQLite reopen
  і cascade delete.
- `GraphConcurrencyTests.swift` — паралельні виклики одного importer-а, окремі
  contexts, великі порції та паралельні зміни графа.
- `GraphSchemaTests.swift` — inverse, порядок і delete rules у моделі.
- `CoreOperationsTests.swift` — identity lookup, batches, rollback, cancellation,
  помилки вхідних даних і owned identity.
- `SchemaMigrationTests.swift` — міграція SQLite при додаванні optional атрибута.
- `CoreDataTestStack.swift` — `NSPersistentContainer`, завантаження `.momd`,
  in-memory або SQLite store, `CoreDataImporter`, fetch і тимчасова SQLite локація.
- `Fixtures/Entities` — окремі `NSManagedObject` класи для восьми Entity.
- `Fixtures/GraphWriter.swift` — вхідні значення та правила запису графа.
- `Fixtures/GraphAssertions.swift` — перевірка всіх збережених Entity та зв’язків.
- `Resources/GraphModel.xcdatamodeld` — вихідна версійна модель Core Data;
  `GraphModel.momd` — її скомпільований ресурс. Кожен SQLite тест створює
  власну тимчасову директорію з файлом `Graph.sqlite`.

У test target немає repository, API, DTO decoding або domain projection. Вхідні
`RootSnapshot`, `SectionSnapshot` і `EntrySnapshot` — прості `Sendable` значення для запису.
Вони не входять у library target.

## Правила зв’язків

| Зв’язок | Правило повного snapshot |
|---|---|
| `Document/Board → Resource` | Ordered membership; `replace` не видаляє спільні ресурси |
| `Folder/Workspace → Resource` | Unordered membership; `replaceUnordered` не видаляє спільні ресурси |
| `Dashboard → Resource` | To-one `featuredResource`; зміна посилання не видаляє старий ресурс |
| Кожен root → `Section` | Ordered owned, ID локальний для root; `reconcileOwned` видаляє surplus |
| `Section → Entry` | Ordered owned, позиція локальна для section; `reconcileOwned` видаляє surplus |

Кожен із п’яти root — окрема Entity зі своїм identity constraint та власними
inverse relationships. `Resource` має глобальний ID і може одночасно належати
різним root таблицям. Перед з’єднанням графа writer пакетно готує всі глобальні
ID; у циклі зв’язування немає fetch. Після кожного сценарію перевіряються всі
root/child/leaf рядки, порядок або membership, унікальність і відсутність
осиротілих owned об’єктів.

Стрес тест пише 251 root кожного типу, по три дитини й два листки на дитину:
1 255 root, 3 765 дітей і 7 530 листків. П’ять конкурентних викликів використовують
один importer: його контракт серіалізує цілі виклики на одному private context.
Окремі SQLite сценарії пишуть і редагують п’ять root таблиць із п’яти private
context одночасно. Вони перевіряють спільні зв’язки та видалення surplus owned
дітей. Повторний import перевіряє відсутність дублікатів; SQLite reopen —
збереження графа на диску.

## Запуск

```sh
swift build
swift test
```

Після зміни `.xcdatamodeld` запустіть `Scripts/update-test-model.sh` і включіть
оновлену `.momd` у ту саму зміну.
