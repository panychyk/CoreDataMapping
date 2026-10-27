# Тестова система: медичний конгрес

Усі тестові файли лежать у `Tests/CoreDataMappingTests/MedicalCongress`:

- `Resources/MedicalCongressModel.xcdatamodeld` — схема Core Data; згенерована
  `.momd` зберігається поруч.
- `Entities` — по одному `NSManagedObject` subclass на Entity.
- `CongressGraphFixture.swift` — маленький граф: конгрес, дві події, три людини, дві
  організації, дві кімнати, два матеріали, сесії та зустрічі.
- `GraphWriter.swift` — тестовий mapper без мережі, decoding, repository чи
  domain-шару.
- `Suites` — п’ять файлів зі сценаріями. Кожен suite містить кілька незалежних
  тестів одного потоку; кожен тест має власний in-memory store.

`CongressTestStack` використовує `NSInMemoryStoreType`. Кожен тест створює
новий store. `GraphAssertions` скидає read context перед перевіркою, звіряє
склад графа й кількість дочірніх записів, перевіряє їхніх власників.

## Правила зв’язків

| Зв’язок | Власник | Правило |
|---|---|---|
| `Congress → CongressEvent` | Окремі root-записи | Видалення конгресу розриває зв’язок із подіями. |
| `Venue → Room` | `Venue` | Видалення місця каскадно видаляє його кімнати. Події та зустрічі лише посилаються на кімнати. |
| `CongressEvent → Track → Session` | Подія й доріжка програми | Повний snapshot узгоджує дочірні записи за локальним ID; пропущені видаляються. |
| `CongressEvent → Appointment → AppointmentParticipant` | Подія й зустріч | Заміна складу видаляє лише зайві записи участі. `Person` і `Room` залишаються. |
| `CongressEvent → Registration → CheckIn` | Подія й реєстрація | Вилучення реєстрації видаляє її check-in; `Person` залишається. |
| `CongressEvent → EventSponsor → Organization` | Подія | Вилучення спонсорства не видаляє організацію. |
| `Session → SessionSpeaker → Person` | Сесія | Вилучення сесії видаляє speaker join, але не людину. |
| `Session ↔ ResourceAsset` | Спільний матеріал | Заміна membership не видаляє матеріал або його зв’язки з іншими сесіями. |

Глобальні `Congress`, `CongressEvent`, `Organization`, `Person`, `Venue`, `Room`
і `ResourceAsset` мають uniqueness constraint на `id`. Дочірні Entity мають
`localID`, який є унікальним лише в межах свого власника. Mapper пакетно
підготовлює глобальні identities перед зв’язуванням і не робить fetch усередині
циклів mapping.

## Що перевіряється

### Модель і початковий запис — `CongressModelAndImportTests`

| Тест | Перевірка |
|---|---|
| `schemaRules` | Усі relationships мають inverse; owned-зв’язки каскадні, спільні — `Nullify`. |
| `identityLookup` | Batch lookup прибирає дублікати ID, пропускає відсутні записи та відхиляє недопустимий розмір fetch-порції. |
| `fullGraphSurvivesContextReset` | Увесь конгрес, дві події, учасники, сесії, зустрічі та їхні зв’язки читаються після reset context. |

### Історія імпортів — `CongressImportHistoryTests`

| Тест | Перевірка |
|---|---|
| `sequentialImports` | Дві послідовні порції створюють цілісний граф двох подій. |
| `repeatedImport` | Повторний повний snapshot використовує ті самі rows, без дублювання зустрічей. |
| `isolatedUpdate` | Оновлення першої події не змінює другу. |
| `multistageHistory` | Після чотирьох збережень зберігаються актуальні shared-зв’язки та owned-записи без «сиріт». |

### Спільні зв’язки — `CongressSharedRelationshipsTests`

| Тест | Перевірка |
|---|---|
| `sharedPerson` | Вилучення людини з однієї зустрічі зберігає її участь в інших зустрічах і реєстраціях. |
| `sharedRoom` | Перенесення зустрічі в іншу кімнату не змінює інші бронювання. |
| `sharedResource` | Відв’язування матеріалу від однієї сесії зберігає його в іншій. |
| `sponsorSnapshot` | Вилучення спонсорства однієї події зберігає організацію та її інше спонсорство. |

### Життєвий цикл дочірніх записів — `CongressOwnedLifecycleTests`

| Тест | Перевірка |
|---|---|
| `participantSnapshot` | Повний snapshot видаляє зайві join rows учасників, не видаляючи людей. |
| `appointmentSnapshot` | Вилучення зустрічі видаляє її учасників, але зберігає людей і кімнати. |
| `sessionSnapshot` | Вилучення сесії видаляє speaker joins, але зберігає матеріали й людей. |
| `registrationSnapshot` | Вилучення реєстрації видаляє її check-ins, але зберігає людину й іншу реєстрацію. |
| `eventDeletion` | Видалення події каскадно видаляє її owned-граф, залишаючи спільні записи. |

### Транзакції імпортера — `CongressTransactionsTests`

| Тест | Перевірка |
|---|---|
| `duplicateOwnedID` | Повторний локальний ID зустрічі відхиляє batch; збережений граф не змінюється. |
| `missingReference` | Посилання на відсутню кімнату відкочує оновлення. |
| `failedBatch` | Помилка в другій порції залишає першу порцію збереженою. |
| `cancellationRollback` | Скасування відкочує поточну порцію, зберігаючи попередній save. |
| `readRollback` | Спроба запису під час `read` відхиляється й не створює row. |
| `concurrentImports` | Один importer серіалізує конкурентні записи двох подій без втрати зв’язків. |

In-memory store не перевіряє повторне відкриття файлу SQLite, WAL або міграцію
моделі між версіями. Для цих перевірок потрібні окремі disk-backed тести.

Після зміни `.xcdatamodeld` запустіть `./Scripts/update-test-model.sh`, потім
`swift build` і `swift test`.
