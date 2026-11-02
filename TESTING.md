# Тестування CoreDataMapping

Цей документ описує наявні тестові системи: їхні графи, правила зв’язків і
сценарії. Правила додавання систем та оформлення suites — в
[AGENTS.md](AGENTS.md).

## Спільна інфраструктура

`Tests/CoreDataMappingTests/Resources/TestModel.xcdatamodeld` — одна Core Data
модель для обох систем. Скомпільована `TestModel.momd` лежить поруч і входить
лише до test target. `Support/TestStack.swift` завантажує модель у
`NSInMemoryStoreType`; кожен тест зі збереженням даних створює власний store.

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
| `CongressTransactionsTests` | Rollback помилкового або скасованого batch, заборона mutation під час read і серіалізація конкурентних імпортів. |

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

## Перевірка

Після зміни моделі запустіть `./Scripts/update-test-model.sh` і збережіть
оновлену `.momd` разом із `.xcdatamodeld`. Для перевірки пакета запустіть
`swift build` і `swift test`.

In-memory тести не перевіряють повторне відкриття SQLite, WAL або міграцію
моделі. Для цього потрібні окремі disk-backed integration tests.
