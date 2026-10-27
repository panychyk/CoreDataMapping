# Практичний посібник: core і зв’язки

Це посібник із використання `CoreDataMapping` у застосунку. Почніть із [README](README.md); інваріанти пакета й межі його відповідальності описані в [ARCHITECTURE.md](ARCHITECTURE.md). Назви вхідних snapshots та Entity у фрагментах коду — приклади; конкретні типи визначає споживач пакета.

Компактний приклад із п’ятьма незалежними root Entity (`Document`, `Folder`,
`Dashboard`, `Board`, `Workspace`) та спільним `Resource` є у
`Tests/CoreDataMappingTests/Fixtures/GraphWriter.swift`; перевірки збережених
Entity — у `Fixtures/GraphAssertions.swift`, сценарії — у `GraphLifecycleTests.swift`
та `GraphConcurrencyTests.swift`. Таблиця relationships — у
[TESTING.md](TESTING.md). Усе це один test target.

## 1. Що робить core

| Частина | Для чого потрібна | Чого не вирішує |
|---|---|---|
| `CoreDataEntityIdentity<Entity, Id>` | Називає Entity, її єдиний атрибут identity та Swift key path до нього | Не конструює ID із вхідних значень і не створює constraint у моделі |
| `CoreDataStorage` | У межах одного context пакетно знаходить/створює записи та допомагає узгодити relationships | Не декодує вхідні дані, не вибирає власника дитини й не викликає `save` |
| `CoreDataImporter` | Виконує `write`, `read` і малі `transaction` на одному private context, серіалізує виклики | Не вирішує, який snapshot новіший і які root-записи видаляти |

Ці три частини містяться у двох файлах пакета: [CoreDataStorage.swift](Sources/CoreDataMapping/CoreDataStorage.swift) (включно з identity) та [CoreDataImporter.swift](Sources/CoreDataMapping/CoreDataImporter.swift). `CoreDataStack`, `.xcdatamodel`, вхідні snapshots і правила запису графа належать споживачу.

**Контракт mapper-а:** він працює лише на черзі context, отриманого через importer, і не передає `NSManagedObject` назовні. Вхідне значення для `write` має бути `Sendable`; результат `read` або `transaction` також має бути `Sendable`. У mapper не викликайте `save`, `rollback` чи `reset`.

Шпаргалка операцій `CoreDataStorage`:

| Виклик | Результат |
|---|---|
| `existing(ids:identifiedBy:)` | Пакетний пошук; відсутні ID пропущені, нові Entity не створюються |
| `upsert(ids:identifiedBy:)` | Пакетний пошук і створення відсутніх Entity з автоматичним присвоєнням identity; scalar-поля заповнює mapper |
| `upsert(_:id:identifiedBy:update:)` | Те саме, а потім `update` для кожного вхідного значення у вхідному порядку |
| `insert(_:)` | Створення Entity без глобального lookup, з моделі поточного context |
| `replace(with:)` / `replaceUnordered(with:)` | Новий набір членів зв’язку без видалення Entity |
| `reconcileOwned` / `deleteSurplusOwned` | Видалення зайвих owned children у **повному** snapshot |

`existing` і обидва `upsert` приймають `prefetching` для relationships, які mapper читатиме. Вони повертають lookup `[Id: Entity]`, що живе лише всередині поточної операції importer-а.

## 2. Мінімальний запис і читання

Для Entity зі стабільним глобальним ID оголосіть у `.xcdatamodel` обов’язковий атрибут `id` та uniqueness constraint на `id`. У Swift-оголошенні додайте descriptor, наприклад:

```swift
nonisolated extension ReservationTopicEntity {
    static let identity = CoreDataEntityIdentity(
        entityName: "ReservationTopicEntity",
        attributeName: #keyPath(ReservationTopicEntity.id),
        keyPath: \ReservationTopicEntity.id
    )
}
```

Коли `topicSnapshots: [TopicSnapshot]` уже підготовлено, використайте `importer`, створений від завантаженого persistent container:

```swift
try await importer.write(topicSnapshots) { batch, storage in
    _ = try storage.upsert(
        batch,
        id: \TopicSnapshot.id,
        identifiedBy: ReservationTopicEntity.identity
    ) { entity, snapshot in
        entity.name = snapshot.name
    }
}

let ids = topicSnapshots.map(\.id)
let names = try await importer.read(ids) { ids, storage in
    let byId = try storage.existing(
        ids: ids,
        identifiedBy: ReservationTopicEntity.identity
    )
    return ids.compactMap { byId[$0]?.name }
}
```

`upsert` спершу готує всі distinct ID, потім оновлює вхідні значення у заданому порядку. Повторний ID отримує останні scalar-значення. `existing` повертає лише знайдені записи; політику для відсутнього обов’язкового root задає код споживача. Жодна з цих операцій не видаляє root, відсутній у вхідному наборі.

`write` зберігає й звільняє context після кожної порції roots (`batchSize`, типово 500). Помилка або скасування відкотить поточну порцію; раніше збережені порції залишаться. `read` іде тією самою чергою, не дозволяє mutations і повертає лише Swift-значення. `transaction` призначено для малої атомарної операції. `fetchChunkSize` у storage окремо обмежує розмір пошуку `IN`; це не розмір commit-порції.

Для кількох операцій, які змінюють спільні записи, передавайте один importer. Після `write` окремий `read` бачить актуальний кеш; між цими викликами може завершитися інший імпорт, тому результат не є ізольованим знімком одного вхідного snapshot.

## 3. Підготувати граф і вибрати операцію для зв’язку

Порядок для batch mapper-а:

1. Для повних повторних root snapshots визначте актуальний snapshot кожного ID **до** поділу на порції. Останній snapshot кожного root має перемагати.
2. Пакетно викличте `upsert` для roots і залежностей із глобальними ID. Для наявних children із parent-scoped ID завантажте relationship батька через `prefetching`.
3. З’єднайте готові об’єкти зі словників `[Id: Entity]`; fetch усередині циклу зв’язування не робіть.
4. Для повного snapshot видаліть лише пропущених **owned** children. Shared-об’єкти залиште в store.

Identity відповідає на «це той самий запис?», ownership — «хто має право його видалити?». Вони незалежні: attendee має глобально унікальний складений ключ, але належить одному appointment.

| Ситуація | Операція в mapper-і при повному snapshot |
|---|---|
| Shared Entity з глобальним ID, наприклад topic або user | `upsert`; для to-one присвоїти `parent.user = usersById[id]`, для to-many — `replace` або `replaceUnordered`. При вилученні зі списку прибрати лише зв’язок |
| Owned child з ID лише всередині батька, наприклад custom field | `reconcileOwned` з **поточними дітьми цього батька**; helper перевикористовує збіги й видаляє зайвих. Повернений список присвоїти relationship |
| Owned child із глобальним або складеним ID, наприклад attendee | `upsert(ids:)` для всього batch, встановити зв’язок, викликати `deleteSurplusOwned` для дітей цього батька |
| Owned child без стабільного ID | Явно зіставити за позицією або бізнес-ключем, створити потрібних і видалити зайвих; позиція не зберігає identity при перестановці |

`replace(with:)` створює ordered membership (`NSOrderedSet`), `replaceUnordered(with:)` — unordered (`Set`). Обидва перевіряють context та стан об’єктів, прибирають повтори й **не видаляють Entity**. Для перевіреного читання ordered relationship є `CoreDataStorage.ordered(...)`; `nil` дає порожній масив, неправильний тип — помилку.

Фрагмент для дитини з ID лише в межах appointment:

```swift
let current = try CoreDataStorage.ordered(
    appointment.customFields,
    as: CustomFieldEntity.self
)
let incoming = try storage.reconcileOwned(
    snapshot.customFields ?? [],
    current: current,
    dtoId: \CustomFieldSnapshot.id,
    entityId: \CustomFieldEntity.id,
    create: { try storage.insert(CustomFieldEntity.self) }
) { field, fieldSnapshot in
    try CustomFieldEntityMapper().update(field, from: fieldSnapshot, using: storage)
    field.appointment = appointment
}
appointment.customFields = try storage.replace(with: incoming)
```

`reconcileOwned` не задає ID нової дитини: це має зробити `update`. Він відхиляє повторний scoped ID у вхідному або поточному списку. `current` не може бути глобальною вибіркою дітей. Для to-one і to-many обидва кінці зв’язку мають належати одному context; scalar `parentId` сам по собі relationship не встановлює.

Якщо child mapper потребує ID батька або словник залежностей, передайте їх параметрами з parent mapper-а. У моделі, яка має обидві властивості, `child.parentId = parent.id` зберігає scalar, а `child.parent = parent` встановлює relationship. Для child → shared user передайте вже підготовлений `usersById`; окремий fetch у child mapper-і не потрібний.

**Повний чи частковий payload:** у прикладі повного snapshot `nil`/відсутня колекція означає `[]` і очищає owned children. Для часткового snapshot такий запис може випадково стерти дані. Розрізняйте «поле не надіслано», `null` і `[]` окремим контрактом вхідних значень та правил запису; не запускайте reconciliation за неповною сторінкою.

## 4. Delete Rule: що станеться при видаленні батька

Delete Rule задається **на relationship від джерела до призначення** у `.xcdatamodel`. Вона діє, коли видаляють екземпляр джерела; просте вилучення елемента з relationship живого батька — інша операція. Для кожного зв’язку задайте inverse і окремо оберіть правило для кожного напрямку.

| Правило на `parent → child` | При видаленні `parent` | Коли обирати |
|---|---|---|
| `Cascade` | Core Data видаляє пов’язаних children | Child належить лише цьому parent і не має жити без нього: `Appointment → attendees/customFields`, `CustomField → multipleValues` |
| `Nullify` | Core Data розриває посилання у зворотному зв’язку; child залишається | Child спільний або має власний життєвий цикл: `Appointment → topics/user/realLocation` |
| `Deny` | Видалення parent не проходить, поки relationship має children | Бізнес-правило вимагає спершу перенести чи явно прибрати залежні записи; обробіть помилку видалення |
| `No Action` | Core Data не оновлює пов’язані об’єкти | Лише якщо застосунок сам узгоджує **всі** зворотні посилання/видалення; інакше можна залишити неконсистентний граф |

Зазвичай `Cascade` підходить для owned, а `Nullify` — для shared. Не ставте `Cascade` на shared-relationship: видалення одного parent тоді видалить запис, потрібний іншим. Для живого parent `Cascade` не замінює reconciliation: коли child зник із повного snapshot, `reconcileOwned` або `deleteSurplusOwned` видаляє його явно. `replace` лише розриває/замінює membership.

Семантика чотирьох правил: [Apple, Configuring Relationships](https://developer.apple.com/documentation/coredata/configuring-relationships). Для `No Action` Apple окремо попереджає про [ризик неузгоджених посилань](https://developer.apple.com/documentation/coredata/nsdeleterule/noactiondeleterule).

## 5. ID із двох властивостей

Якщо `childId` унікальний лише в межах parent і ви завжди працюєте з дітьми одного parent, вистачає `reconcileOwned(current: ...)`. Однаковий `childId` у двох батьків тоді є двома різними Entity.

Коли child потрібен для **пакетного глобального lookup**, створіть стабільний persistence ID з обох частин. Наприклад, `AppointmentAttendeeEntity.makeId` отримує два `Int`:

```swift
static func makeId(appointmentId: Int, userId: Int) -> String {
    "\(appointmentId)_\(userId)"
}
```

Для цієї пари цілих чисел ключ однозначний. У схемі `AppointmentAttendeeEntity.id` — обов’язковий `String` з uniqueness constraint. Mapper рахує ключі для **всього batch** до зв’язування:

```swift
let attendeeIds = batch.flatMap { dto in
    (dto.Attendees ?? []).map { attendee in
        AppointmentAttendeeEntity.makeId(
            appointmentId: dto.RoomReservationUserID,
            userId: attendee.UserID
        )
    }
}
let attendeesById = try storage.upsert(
    ids: attendeeIds,
    identifiedBy: AppointmentAttendeeEntity.identity
)
```

Під час з’єднання використайте **ту саму** `makeId`, візьміть Entity з `attendeesById`, задайте `attendee.appointment` і `attendee.user`, присвойте `appointment.attendees`, після цього видаліть surplus owned children.

Для довільних рядкових частин просте `"\(a)_\(b)"` може дати колізію: пари `("a_b", "c")` і `("a", "b_c")` дадуть той самий рядок. Один із варіантів однозначного кодування:

```swift
static func makeId(parentId: String, childId: String) -> String {
    "\(parentId.utf8.count):\(parentId)\(childId.utf8.count):\(childId)"
}
```

Перевірте обраний формат тестом. Якщо він зміниться після випуску застосунку, потрібна міграція існуючих записів.

Core Data дозволяє uniqueness constraint із кількох атрибутів, але поточний `CoreDataEntityIdentity`/`CoreDataStorage.existing` шукає через **один** identity-атрибут. Для lookup за двома окремими колонками потрібно розширювати core; сам багатопольовий constraint цього пошуку не додає. Див. [Apple, uniquenessConstraints](https://developer.apple.com/documentation/coredata/nsentitydescription/uniquenessconstraints).

## 6. Якщо відповідь не є простим повним snapshot

| Ситуація | Рішення на рівні graph writer |
|---|---|
| API повертає сторінки | Не видаляйте дітей після однієї неповної сторінки. Узгодьте повний snapshot батька після отримання всіх сторінок або задайте окрему політику merge |
| Root зник із повного списку | `upsert` сам його не видаляє. Код споживача має отримати deleted IDs або порівняти повний список у потрібному scope й явно видалити root |
| Циклічні зв’язки або лише ID залежності | Спочатку підготуйте identities всіх потрібних типів, потім з’єднайте граф. Для відсутньої залежності явно оберіть помилку, відкладений зв’язок або валідний placeholder |
| Кілька повних snapshots одного root | Залиште останній snapshot перед поділом на batch, інакше старіший snapshot може зайво видалити й створити owned children |

## 7. Коротка перевірка перед використанням

- Новий граф проходить create → save → repeat → update → remove → reload без дубльованих дітей.
- Shared-записи переживають розрив зв’язку й видалення одного з батьків; owned-записи зникають після видалення свого батька.
- Однакові scoped child IDs у різних батьків не змішуються; складений ключ не має колізій.
- Усі `NSManagedObject` використовуються на черзі свого context. Потрібні relationships завантажені через `prefetching`, а не окремими fetch у циклі.
- Зміна моделі Core Data у застосунку супроводжується Swift-оголошеннями Entity, кодом запису та SQLite integration tests. Після зміни тестової `.xcdatamodeld` цього пакета запустіть `Scripts/update-test-model.sh` і збережіть `.momd` разом із нею.
