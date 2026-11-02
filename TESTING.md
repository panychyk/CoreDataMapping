# Тестування CoreDataMapping

Цей документ описує наявні тестові системи: їхні графи, правила зв’язків і
сценарії. Правила додавання систем та оформлення suites — в
[AGENTS.md](AGENTS.md).

## Спільна інфраструктура

`Tests/CoreDataMappingTests/Resources/TestModel.xcdatamodeld` — одна Core Data
модель для чотирьох систем. Скомпільована `TestModel.momd` лежить поруч і входить
лише до test target. `Support/TestStack.swift` завантажує модель у
`NSInMemoryStoreType` за замовчуванням; кожен тест зі збереженням даних створює
власний store. SQLite integration tests передають stack URL тимчасового store.

`Integration/Suites/SQLiteReopenTests.swift` перевіряє повний граф конгресу
після відкриття store новим container, а також оновлення замовлення маркетплейсу
після двох послідовних відкриттів. Він також перевіряє конгрес після скасування
другої порції, наступного успішного запису й нового відкриття. Кожен тест має
власний файл SQLite.

## MedicalCongress

`MedicalCongress/Entities/` містить 15 класів Entity. Поруч лежать
`CongressGraphFixture.swift`,
`GraphWriter.swift`, `GraphAssertions.swift`, `CongressTestStack.swift` і
`Suites/`. Фікстура має конгрес із двома подіями; люди, кімнати, організації та
матеріали використовуються в кількох частинах графа.

| Зв’язок | Правило |
|---|---|
| `Congress → CongressEvent` | Події — окремі root-записи; видалення конгресу розриває зв’язок. |
| `Venue → Room` | Кімнати належать місцю проведення; видалення venue каскадне. |
| `CongressEvent → Track → Session` | Подія володіє tracks, track — sessions; повний snapshot узгоджує їх за локальним ID. |
| `CongressEvent → Appointment / Registration / EventSponsor` | Подія володіє зустрічами, реєстраціями й записами спонсорства та їхніми дочірніми join rows. |
| `Session ↔ ResourceAsset` | Матеріали спільні; зміна membership не видаляє їх. |
| `Person`, `Room`, `Organization` у дочірньому графі | Посилання на спільні записи не передають дочірнім Entity права на їх видалення. |

Глобальні `Congress`, `CongressEvent`, `Organization`, `Person`, `Venue`, `Room`
і `ResourceAsset` мають uniqueness constraint на `id`. `localID` дочірніх Entity
унікальний лише в межах власника.

| Suite | Сценарій |
|---|---|
| `CongressModelAndImportTests` | Правила схеми, batch identity lookup і перший запис повного графа. |
| `CongressImportHistoryTests` | Послідовні та повторні імпорти, ізольоване оновлення події й історія з кількох збережень. |
| `CongressSharedRelationshipsTests` | Зміна зв’язків із людьми, кімнатами, матеріалами й організаціями без втрати їхнього іншого використання. |
| `CongressOwnedLifecycleTests` | Reconciliation і каскадне видалення дочірніх записів без видалення спільних Entity. |
| `CongressTransactionsTests` | Rollback помилкового або скасованого batch, відкат після помилки Core Data під час save з успішним повтором, заборона mutation під час read і серіалізація конкурентних імпортів. |
| `CongressImporterContractTests` | Серіалізація багатопорційних write/read після постановки другого виклику в чергу, порядок результатів read, commit/rollback transaction та граничні розміри batch. |
| `CongressControlledConcurrencyTests` | Керовані бар’єрами два snapshots однієї події з читанням через окремий context; перекриття записів двох подій, rollback другого та успішний повтор. |
| `CongressComplexTransitionsTests` | Багаторівневий snapshot з перестановкою, повторними локальними ID та збереженням identity; пізній збій другої порції, відкат і успішний повтор. |
| `CongressStorageContractsTests` | Прямі контракти storage: повторні глобальні ID, видалення owned дітей і помилки Entity та relationship helpers. |
| `CongressFetchPerformanceTests` | Кількість fetch-запитів при повторному імпорті не зростає зі збільшенням числа подій (1 → 8) або сесій однієї події (1 → 8). |

## Marketplace

`Marketplace/Entities/` містить 11 класів Entity. Поруч лежать
`MarketplaceGraphFixture.swift`,
`MarketplaceGraphWriter.swift`, `MarketplaceGraphAssertions.swift`,
`MarketplaceTestStack.swift` і `Suites/`. Фікстура має два замовлення зі спільним
товаром та однаковими локальними ID позицій. Це перевіряє, що позиція належить
конкретному замовленню.

| Зв’язок | Правило |
|---|---|
| `Seller → Product` | Товар належить продавцю; видалення продавця каскадно видаляє його товари. |
| `Product ↔ Category` | Категорії спільні; зміна membership не видаляє категорії. |
| `Product → OrderItem ← Order` | Товар може бути в багатьох замовленнях; позиція належить лише своєму замовленню. |
| `Product → Stock ← Warehouse` | Залишок має глобальний ID і посилається на товар та склад. |
| `Order → Payment / Shipment` | Платежі й доставки належать замовленню; повний snapshot узгоджує лише його дітей. |
| `Buyer → Order / Review`, `Product → Review` | Покупець спільний; відгук має глобальний ID і посилається на товар. |

Глобальні buyers, sellers, products, categories, warehouses, stocks, orders і
reviews мають identity `id`. `localID` позицій, платежів і доставок
унікальний у межах свого замовлення.

| Suite | Сценарій |
|---|---|
| `MarketplaceModelAndImportTests` | Правила схеми та перший запис усього графа. |
| `MarketplaceImportHistoryTests` | Повторний імпорт та оновлення одного замовлення без зміни іншого. |
| `MarketplaceSharedRelationshipsTests` | Зміна категорій і залишку зі збереженням спільних зв’язків. |
| `MarketplaceOwnedLifecycleTests` | Вилучення платежу, доставки та замовлення з очищенням лише його дітей. |
| `MarketplaceTransactionsTests` | Rollback після дубльованого локального ID або відсутнього товару. |

## University

`University/Entities/` містить 12 класів Entity. Поруч лежать
`UniversityGraphFixture.swift`, `UniversityGraphWriter.swift`,
`UniversityGraphAssertions.swift`, `UniversityTestStack.swift` і `Suites/`.
Мала фікстура має два факультети, дві програми, три групи, три студенти,
два курси і три проведення. Курс Algorithms проводиться у двох семестрах;
студент Ada записаний на три проведення. Локальні ID записів, завдань і
оцінок повторюються в різних власників.

| Зв’язок | Правило |
|---|---|
| `Faculty → Program → Course / Group / Student` | Довідникові Entity мають глобальний `id`; зв’язки з факультетом і програмою розриваються без каскадного видалення. Студент належить одній групі, але може мати багато записів. |
| `Course / Semester / Teacher / Room → Offering` | Проведення має глобальний `id`. Курс, семестр, викладач і аудиторія спільні; видалення проведення їх не видаляє. |
| `Offering → Assignment / Enrollment` | Проведення володіє завданнями й записами, локальний `localID` унікальний у його межах. Повний snapshot узгоджує лише дітей конкретного проведення. |
| `Enrollment → Grade → Assignment` | Запис володіє оцінками з локальним `localID`; оцінка посилається тільки на завдання того самого проведення. Повний snapshot видаляє відсутні оцінки. |

| Suite | Сценарій |
|---|---|
| `UniversityModelAndImportTests` | Inverse, delete rules, identity constraints і перший запис повного графа. |
| `UniversityImportHistoryTests` | Послідовні імпорти, повторне використання objectID і незалежне оновлення проведення. |
| `UniversityRelationshipsAndLifecycleTests` | Переміщення спільних посилань, reconciliation дітей і каскадне видалення проведення. |
| `UniversityTransactionsTests` | Rollback дубльованих ID, хибних посилань, повторного запису студента та збереження попереднього batch. |

## TravelBooking

`TravelBooking/Entities/` містить 11 класів Entity. `TravelGraphFixture.swift`
описує три поїздки двох напрямків: два мандрівники користуються тим самим
рейсом і номером, третій має інший маршрут. У різних поїздках і бронюваннях
повторюються локальні ID бронювань, гостей, платежів і квитків.

| Зв’язок | Правило |
|---|---|
| `Traveler → Trip` | Мандрівник є спільним записом із глобальним `id`; поїздка має окремий глобальний `id`. Видалення мандрівника не видаляє поїздки. |
| `Trip → Booking → Guest / Payment / Ticket` | Поїздка володіє бронюваннями, а бронювання — дочірніми записами. Повний snapshot узгоджує їх за `localID` лише в межах власника; видалення каскадне. |
| `Booking → Flight / Room` | Бронювання посилається рівно на один із цих спільних записів. Зміна маршруту або скасування не видаляє рейс чи номер. |
| `Flight → Airport`, `Room → Hotel`, `Traveler → Loyalty` | Глобальні довідникові записи зберігаються при зміні membership; аеропорт може бути і пунктом прибуття, і пунктом відправлення. |
| `Ticket → Guest` | Квиток посилається лише на гостя того самого бронювання; місце унікальне в межах бронювання. |

| Suite | Сценарій |
|---|---|
| `TravelModelAndImportTests` | Inverse, delete rules, повний граф і повторне використання рейсу та номера. |
| `TravelHistoryAndLifecycleTests` | Окремі batch, повторний імпорт зі сталими objectID, перебронювання, зміна спільного каталогу, reconciliation та каскадне видалення. |
| `TravelTransactionsTests` | Відкат дубльованого платежу, місця, хибного гостя квитка, некоректного типу бронювання й пізнішого batch. |

## Перевірка

Після зміни моделі запустіть `./Scripts/update-test-model.sh` і збережіть
оновлену `.momd` разом із `.xcdatamodeld`. Для перевірки пакета запустіть
`swift build` і `swift test`.

In-memory тести не перевіряють повторне відкриття SQLite; це роблять окремі
disk-backed integration tests. Поведінка WAL та міграція моделі наразі не
перевіряються.

Лічильник у `CongressFetchPerformanceTests` вимірює fetch-запити, передані
`NSPersistentStoreCoordinator`, а не кількість SQL-запитів у SQLite.
`GraphAssertions` додатково звіряє сирий порядок `NSOrderedSet.array` після
скидання read context; той самий assert виконується після відкриття SQLite.
