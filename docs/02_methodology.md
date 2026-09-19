## Методология

### Предобработка
Проведено 17 проверок в [01_preprocessing.sql](https://github.com/dianaborisova3/Yousell_funnel_analysis/blob/main/sql/01_preparation.sql):
- Профиль 4 таблиц (объем, диапазон дат, уникальные ключи).
- Проверка дублей, потерянных действий (есть в одной таблице, но нет в другой), NULL в ключах.
- Проверка заполнения order_id по типам событий.
- Проверка логики воронки (Purchase без Cart, Cart без View).
- Проверка гипотезы об обязательности этапа воронки Checkout (13–15).

Результаты:
- Дубли: 0. Потерянных действий по клиентам: 0, по товарам: 0.
- NULL в ключевых полях: отсутствуют.
- Purchase без order_id: 0, заказы без Purchase-лога: 0.
- Клиенты без действий: 2 601 (26%).
- Данные чистые, дополнительная фильтрация не требуется.

### Значения event_type
Четыре типа событий (с заглавными буквами):
- Page View - 80 432 события;
- Add to Cart - 33 176;
- Checkout - 7 687;
- Purchase - 5 110.

### Ключевое решение: Checkout исключен из воронки
Проверки 13–15 в preprocessing показали:
- 789 покупателей (24.75%) никогда не делали Checkout;
- 903 покупателя имеют Purchase до первого Checkout;
- 2 326 из 5 110 покупок (45.5%) не имеют предшествующего Checkout;
- у Checkout отсутствует order_id - связать с заказом нельзя.

Вывод: 
- Checkout не является обязательным шагом.
- Воронка построена из трех шагов: Page View - Add to Cart - Purchase.
- Checkout рассматривается отдельно как справочная метрика.

### Уровень агрегации в разрезах
- [Общая воронка](https://github.com/dianaborisova3/Yousell_funnel_analysis/blob/main/sql/02_funnel.sql): уровень пользователя.
- [По категориям](https://github.com/dianaborisova3/Yousell_funnel_analysis/blob/main/sql/03_funnel_categories.sql): уровень пары (пользователь, категория). Один пользователь может присутствовать в нескольких категориях, потому что смотрит товары в разных категориях.
- [По городам](https://github.com/dianaborisova3/Yousell_funnel_analysis/blob/main/sql/04_funnel_city.sql) и [демографии](https://github.com/dianaborisova3/Yousell_funnel_analysis/blob/main/sql/05_funnel_age_gender.sql): уровень пользователя (у одного пользователя один город и одна возрастная группа).

### Установление категорий для действия Purchase
- У Purchase product_id = NULL, так как заказ содержит несколько товаров. 
- Установление категорий выполнено через customer_actions (Purchase) - order_id - order_items - product_id (product_category_name).
- Если в заказе несколько категорий, пользователь учитывается как покупатель в каждой из них.
