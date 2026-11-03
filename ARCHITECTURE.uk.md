# CoreDataMapping: архітектура та інваріанти

Мова: [English](ARCHITECTURE.md) · **Українська**

Практичні приклади — у [CORE_GUIDE.md](CORE_GUIDE.uk.md). Пакет містить тільки
універсальні persistence helpers. DTO, `NSManagedObject` subclasses, модель Core Data,
container, networking, feature mappers і repositories визначає застосунок.

## Публічний API

| Компонент | Відповідальність |
|---|---|
| `CoreDataEntityIdentity` | Назва Entity, обов'язковий identity-атрибут, Swift key path |
| `CoreDataStorage` | Batch lookup/upsert, створення Entity, membership і reconciliation owned children у межах одного context |
| `CoreDataImporter` | Послідовні `write`, `read` і `transaction` на private context, bounded batches, save/rollback/reset |

Пакет не декодує DTO й не обходить граф автоматично. Mapper явно встановлює scalar
fields і relationships; він не викликає `save`, `rollback` або `reset`.

`Tests/CoreDataMappingTests/Resources/TestModel.xcdatamodeld` — одна спільна
тестова схема з 49 Entity: 15 для медичного конгресу, 11 для маркетплейсу,
12 для університету й 11 для бронювання подорожей.
`Support/TestStack.swift` завантажує її в окремий `NSInMemoryStoreType` для
кожного тесту. У `MedicalCongress`, `Marketplace`, `University` і
`TravelBooking` лежать власні `NSManagedObject` класи, невеликі графи,
правила запису та сценарії. Схема й фікстури не входять до library target;
у test target немає мережевого, repository чи domain-шару.
Стратегія тестів і опис зв’язків — у [TESTING.md](TESTING.md).

## Context і concurrency

Застосунок створює `NSPersistentContainer`, завантажує store та передає importer-у
`newBackgroundContext()`. `CoreDataImporter(context:)` вимагає private-queue context,
напряму підключений до store coordinator. Цим context користується тільки importer.
Пакет не шукає модель у `Bundle.main` і не створює persistent store.

`NSManagedObject` залишається на черзі свого context. У mapper closure не передавайте
managed objects назовні чи в інший context; назовні повертайте `Sendable` значення.
DTO для `write` і результат `read`/`transaction` також мають бути `Sendable`.
Пов'язані Entity у межах одного mapping call належать тому самому context.

Один виклик `write` або `read` виконується в одному enqueued `context.perform` block:
порції конкурентних викликів не перемішуються. У кожній порції порядок такий:
map → cancellation check → save за наявності змін → reset. Помилка або скасування
до save відкочує поточну порцію; раніше збережені порції залишаються. Скасування
кооперативне й не перериває вже запущений SQLite save. Undo вимкнений,
тимчасові Objective-C allocations обмежені autoreleasepool.

`read` відхиляє mutation через `CoreDataImportError.mutationDuringRead` і накопичує
лише Swift values. `transaction` — одна атомарна мала операція, а не спосіб
обробити необмежений набір даних. Окремі `write` та `read` не утворюють спільну
транзакцію: між ними може завершитися інший import.

## Identity, lookup і пам'ять

Entity зі стабільною глобальною identity має обов'язковий атрибут, відповідний
Core Data uniqueness constraint і `CoreDataEntityIdentity`. `existing(ids:)`
пакетно шукає записи та повертає тільки знайдені. `upsert(ids:)` додатково створює
відсутні та задає identity; `upsert(_:id:identifiedBy:update:)` оновлює scalar
fields у вхідному порядку. Для повторних ID останній DTO перемагає. `upsert`
не видаляє rows, пропущені у payload.

`CoreDataEntityIdentity` описує **один** persistence-атрибут. Для глобального
lookup за двома складниками mapper створює стабільний однозначний складений ID
в одному атрибуті. Багатопольовий uniqueness constraint сам по собі не розширює
API пошуку `CoreDataStorage`.

`batchSize` importer-а обмежує кількість root DTO у commit; `fetchChunkSize`
storage окремо обмежує розмір `IN` predicate. Обидва за замовчуванням дорівнюють
500. Вони не обмежують великий граф одного parent чи розмір уже декодованої
масиву DTO. Для наскрізного обмеження пам'яті потрібні server pages або
порційний decoder. `prefetching` задавайте для relationships, які mapper читатиме;
наявність fault queries перевіряйте profiling.

## Ownership і snapshots

| Identity / ownership | Matching | Відсутній child у повному snapshot |
|---|---|---|
| Global, shared | Batch `upsert` | Розірвати зв'язок; row залишається |
| Global/composite, owned | Batch `upsert` | `deleteSurplusOwned` для children цього parent |
| Parent-scoped, owned | `reconcileOwned` серед children цього parent | Видалити |
| Без стабільного ID, owned | Явне зіставлення за позицією або бізнес-ключем | Видалити |

`reconcileOwned` працює лише з уже завантаженими дітьми **одного** parent. Він
перевіряє повторні ID, перевикористовує наявні Entity та видаляє surplus;
`update` мусить задавати ID новій дитині. `deleteSurplusOwned` і reconciliation
застосовують лише до owned children повного snapshot. Для partial payload
mapper окремо визначає merge semantics. `replace` і `replaceUnordered` змінюють
membership, але не видаляють Entity. Relationship helpers перевіряють context
та стан об'єктів; `CoreDataStorage.ordered` перевіряє тип елементів.

Mapper спочатку готує identities усіх roots і залежностей, а потім з'єднує граф
через локальні lookup dictionaries. Fetch усередині mapping/update/relationship
loop не допускається. Для повторних повних snapshots одного root mapper має
визначити актуальний DTO **до** поділу на порції. Importer не знає identity DTO,
новизну server snapshots або політику видалення root.

Delete rules, inverse relationships і uniqueness constraints визначає модель
застосунку. Для parent → owned зазвичай використовують `Cascade`, для parent →
shared — `Nullify`; видалення parent і вилучення child із snapshot є різними
операціями. Детальні приклади — у [CORE_GUIDE.md](CORE_GUIDE.uk.md).

## Кілька importer-ів

Починайте з одного спільного importer-а для repositories, які пишуть у той самий
store або перетинаються за root/shared identities чи relationships. API requests
і decoding можуть іти паралельно; mapping на одному importer-і серіалізований.
Один importer не обирає новішу із суперечливих серверних відповідей — це правило
визначає застосунок.

Для незалежних груп запису можна створити окремі private contexts і importer-и.
Незалежність визначають за фактичними scalar fields, shared IDs, relationships
та owned children, а не за назвами endpoints. Між contexts не передають
`NSManagedObject`; коли потрібно, використовують permanent object ID або
повторне читання у context одержувача. Merge policy і uniqueness constraints
не визначають правильну серверну версію. Перед паралельними записами потрібні
тести цілісності графа та вимірювання на реальному навантаженні.

## Корисні джерела

- [Core Data performance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/Performance.html)
- [Core Data concurrency](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/Concurrency.html)
- [Core Data uniqueness constraints](https://developer.apple.com/documentation/coredata/configuring-entities)
- [Core Data merge policy](https://developer.apple.com/documentation/coredata/nsmergebypropertyobjecttrumpmergepolicy)
