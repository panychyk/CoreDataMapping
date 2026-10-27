# Тести й зв’язки прикладу

## Структура

`Sources/CoreDataMapping` містить лише три універсальні типи пакета.
`Tests/CoreDataMappingTests/Example` містить перенесені DTO, domain-моделі,
Entity, мапери, repositories і тестовий API client. Усі вони компілюються в
test target; застосунку для запуску тестів більше не потрібно.
Це інтеграційний приклад реального графа. З часом його можна скоротити, але
варто зберегти показові зв’язки shared, owned, ordered і складений ID.

Схема лежить у `Tests/CoreDataMappingTests/Resources/PersistenceModel.xcdatamodeld`.
SwiftPM CLI копіює `.xcdatamodeld` як ресурс, тому тестовий `CoreDataStack`
завантажує скомпільовану `PersistenceModel.momd` із `Bundle.module`. Після
редагування схеми запустіть `Scripts/update-test-model.sh` і збережіть обидві
версії моделі. `swift test` запускає також інтеграційні SQLite та migration-тести.

## Як описувати relationship

Для кожного зв’язку зафіксуйте чотири рішення: стабільний ID об’єкта, власника
його життєвого циклу, порядок колекції та значення відсутнього поля у payload.
У `.xcdatamodel` вкажіть destination, inverse, cardinality, ordered і delete
rule **для кожного напрямку**. У Swift Entity оголосіть відповідні `@NSManaged`
властивості, а mapper явно встановлює саме relationship, не лише scalar ID.

| Зв’язок у тестовій схемі | Ownership та identity | Модель і mapping повного snapshot |
|---|---|---|
| `Appointment → attendees` | Owned; ID `appointmentId_userId` | Unordered, inverse `appointment`, `Cascade`; batch `upsert`, потім `deleteSurplusOwned` |
| `Appointment → customFields → multipleValues` | Owned; ID поля лише в межах parent | Ordered fields, unordered values, `Cascade`; `reconcileOwned` серед дітей одного parent |
| `Appointment → topics` | Shared; глобальний `topicId` | Ordered, inverse `appointments`, `Nullify`; batch `upsert` і `replace`; вилучення зі списку не видаляє topic row |
| `Appointment → user/realLocation` | Shared; глобальні ID | To-one, `Nullify`; змінити посилання на підготовлений об’єкт, старий shared row залишити |
| `ScheduleEvent/Elective → tracks/facilitators` | Shared; глобальні ID | Ordered, `Nullify`; підготувати залежності пакетом, потім `replace` |
| `ScheduleEvent → reservation` | Owned; окремий ID reservation | To-one, `Cascade`; відсутність у повному snapshot очищає й видаляє owned row |

`Cascade` спрацьовує при видаленні parent. Якщо child зник із **живого** parent
у повному snapshot, mapper сам видаляє owned child. `replace` змінює membership
без видалення rows. Для partial payload не перетворюйте відсутнє поле на
порожню колекцію: спочатку визначте merge semantics API. Детальний порядок
`upsert → link → reconcile` є в [CORE_GUIDE.md](CORE_GUIDE.md).

## Які тести писати

Нову можливість починайте з правила конкретного зв’язку: визначте identity,
ownership, порядок і семантику відсутнього поля. Перевірте правило тестом на
малому графі з DTO-фабрики, а потім змінюйте універсальний код пакета.

1. **Контракт DTO:** короткий JSON лише для формату, який задає сервер: назви
   ключів, enum raw values, nullable поля, дати й envelope. Зразки є в
   `AppointmentDTOTests` і `ProgramContractTests`.
2. **Mapper:** створюйте невеликі DTO через `TestDTOFactory`; перевіряйте
   insert, повторний import, зміну order/membership, видалення owned child,
   збереження shared row та два parent з однаковим scoped child ID.
3. **SQLite integration:** використовуйте тимчасовий store, save, reset/reopen;
   перевіряйте цілісність графа, uniqueness, rollback, cancellation і міграцію.
   In-memory store не перевіряє все те саме.
4. **Batch boundary:** згенеруйте трохи більше за `batchSize` roots, як у
   `AppointmentRepositoryTests`, без багатомегабайтного JSON.
5. **Schema contract:** `RelationshipSchemaTests` перевіряє inverses, delete
   rules і ordered collection у скомпільованій моделі.

Великий JSON-відбиток відповіді сервера доречний лише для окремого contract
regression або benchmark, коли важлива саме реальна форма payload. Він не має
бути обов’язковим ресурсом модульного тесту: такі файли важко переглянути й
вони прив’язують тест до випадкового обсягу відповіді. Синтетичне навантаження
краще будувати детермінованою фабрикою з явними fan-out і кількістю roots.
Початковий benchmark-код збережено в `Benchmarks/` як довідку; він не входить у
`swift test` і його тести з великими bundled відповідями потребують окремих
даних для повторного запуску.

## Запуск

```sh
swift build
swift test
```
