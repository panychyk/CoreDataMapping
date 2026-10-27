# Тестова система: медичний конгрес

Усі тестові файли лежать у `Tests/CoreDataMappingTests/MedicalCongress`:

- `Resources/MedicalCongressModel.xcdatamodeld` — схема Core Data; згенерована
  `.momd` зберігається поруч.
- `Entities` — по одному `NSManagedObject` subclass на Entity.
- `GraphCases.swift` — маленький граф: конгрес, дві події, три людини, дві
  організації, дві кімнати, два матеріали, сесії та зустрічі.
- `GraphWriter.swift` — тестовий mapper без мережі, decoding, repository чи
  domain-шару.
- `Cases` — один файл і один test suite для кожного сценарію.

`CongressTestStack` використовує `NSInMemoryStoreType`. Кожен сценарій створює
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

Сценарії охоплюють повний запис і читання після reset context, повторне та
послідовне збереження, спільних людей/кімнати/матеріали, узгодження дочірніх
записів, відсутність «сиріт», каскадне видалення події, ідентичність і batch
lookup, конкуренцію на одному importer, rollback помилки та cancellation.

In-memory store не перевіряє повторне відкриття файлу SQLite, WAL або міграцію
моделі між версіями. Для цих перевірок потрібні окремі disk-backed тести.

Після зміни `.xcdatamodeld` запустіть `./Scripts/update-test-model.sh`, потім
`swift build` і `swift test`.
