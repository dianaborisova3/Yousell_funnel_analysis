-- ============================================================
-- Маркетплейс YouSell: воронка действий пользователя
-- Этап 1. Предобработка данных и проверка логических аномалий
-- ============================================================
-- ВАЖНО: Redash выполняет только один запрос за раз.
-- Файл собран целиком для портфолио и чтения логики.
-- При работе в Redash каждый блок запускается отдельно.
-- ============================================================

-- 1. Посмотрим основные характеристики таблицы customer_actions
SELECT
  COUNT(*) AS total_rows,  -- общее количество строк
  COUNT(DISTINCT customer_id) AS unique_users,  -- уникальных пользователей в логах
  COUNT(DISTINCT order_id) AS unique_orders,  -- уникальных заказов
  COUNT(DISTINCT product_id) AS unique_products,  -- уникальных продуктов заказано
  MIN(event_timestamp) AS first_event,  -- первое событие
  MAX(event_timestamp) AS last_event,  -- последнее событие
  COUNT(DISTINCT DATE_TRUNC('day', event_timestamp)) AS active_days -- активных дней на сайте
FROM
  customer_actions;

-- 2. Проверим характеристики видов событий в customer_actions
SELECT
  event_type,
  COUNT(*) AS events,  -- общее кол-во строк
  COUNT(DISTINCT customer_id) AS users,  -- уникальных пользователей по событиям
  COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_user,  -- кол-во событий без пользователя
  COUNT(*) FILTER (WHERE event_timestamp IS NULL) AS null_timestamp, -- кол-во событий без указания времени
  COUNT(order_id) AS with_order_id,  -- событие с order_id 
  COUNT(*) FILTER (WHERE order_id IS NULL) AS no_order_id,  -- событие без order_id
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS percent_of_events -- доля события от общего числа событий
FROM
  customer_actions
GROUP BY
  event_type
ORDER BY
  events DESC;

-- 3. Посмотрим основные характеристики таблицы customers
SELECT 
  COUNT(*) AS total_customers, -- общее кол-во пользователей
  COUNT(DISTINCT customer_id) AS unique_customers,  -- кол-во уникальных пользователей
  COUNT(*) FILTER (WHERE gender IS NULL) AS null_gender,  -- без указания пола
  COUNT(*) FILTER (WHERE birth_date IS NULL) AS null_birth_date,  -- без указания даты рождения
  COUNT(*) FILTER (WHERE customer_city IS NULL) AS null_city,  -- без указания города
  MIN(created_at) AS first_registration,  -- первая дата регистрации
  MAX(created_at) AS last_registration  -- последняя дата регистрации
FROM 
  customers;

-- 4. Посмотрим основные характеристики таблицы products
SELECT
  COUNT(*) AS total_products,  -- общее кол-во товаров
  COUNT(DISTINCT product_id) AS unique_products,  -- кол-во уникальных товаров
  COUNT(DISTINCT product_category_name) AS unique_categories,  -- кол-во уникальных категорий
  COUNT(*) FILTER (WHERE product_category_name IS NULL) AS null_category  -- товаров без категорий
FROM 
  products;

-- 5. Посмотрим основные характеристики таблицы orders
SELECT
  COUNT(*) AS total_orders,  -- общее кол-во заказов
  COUNT(DISTINCT customer_id) AS unique_customers,  -- кол-во уникальных покупателей
  COUNT(DISTINCT order_id) AS unique_orders,  -- кол-во уникальных заказов
  MIN(order_created_time) AS first_order,
  MAX(order_created_time) AS last_order
FROM 
  orders;

-- 6. Проверим характеристики статусов в orders
SELECT
  order_status,
  COUNT(*) AS total_orders,  -- кол-во заказов
  COUNT(*) FILTER (WHERE order_status IS NULL) AS null_status,  -- заказов без статуса
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent_of_orders  -- доля заказов по статусу от общего числа в %
FROM
  orders
GROUP BY
  order_status
ORDER BY total_orders DESC;

-- Проверяем логические аномалии в данных

-- 7. Наличие дублирующихся строк в логах действий клиентов
WITH duplicates AS(
  SELECT
    customer_id,
    event_timestamp,
    event_type,
    product_id,
    COUNT(*) AS cnt  -- кол-во строк по условию группировки
  FROM
    customer_actions
  GROUP BY
    customer_id,
    event_timestamp,
    event_type,
    product_id
  HAVING
    COUNT(*) > 1  -- оставляем только строки, где под условие подошло более 1 строки
)
SELECT
  COUNT(*) AS duplic_groups,
  COALESCE(SUM(cnt - 1), 0) AS extra_rows
FROM 
  duplicates;

-- 8. Действия, где клиента нет в полном списке клиентов
SELECT
  COUNT(*) AS actions_no_user
FROM
  customer_actions ca
LEFT JOIN customers c USING (customer_id)
WHERE 
  ca.customer_id IS NOT NULL AND c.customer_id IS NULL;

-- 9. Действия, где продукта нет в полном списке продуктов
SELECT
  COUNT(*) AS actions_no_product
FROM
  customer_actions ca
LEFT JOIN products p USING (product_id)
WHERE
  ca.product_id IS NOT NULL AND p.product_id IS NULL;

-- 10. Клиенты, не дошедшие до воронки
SELECT
  COUNT(*) AS customers_without_actions
FROM
  customers c
LEFT JOIN customer_actions ca USING (customer_id)
WHERE
  ca.customer_id IS NULL;

-- 11. Действие покупки без номера заказа
SELECT
  COUNT(*) AS purchases_without_order  -- кол-во действий
FROM
  customer_actions
WHERE
  event_type = 'Purchase' AND order_id IS NULL;  -- со статусом 'Purchase', без номера заказа

-- 12. Заказы из orders без логов о покупке в customer_actions
SELECT
  COUNT(*) AS order_no_log  -- кол-во строк, удовлетворяющих подзапросу
FROM 
  orders o
WHERE NOT EXISTS (  -- оставляет заказы, для которых подзапрос ничего не нашел
  SELECT 1 
  FROM customer_actions ca
  WHERE 
    ca.order_id = o.order_id AND ca.event_type = 'Purchase'
);  -- по номеру заказа и действию

-- Нам известны 4 события в логах ('Page View', 'Add to cart', 'Checkout', 'Purchase'),
-- которые должны следовать друг за другом. Проверим, что логика не нарушена.

-- 13. Пользователи есть в 'Purchase', но нет в 'Checkout'
WITH events_by_user AS(
    SELECT 
      customer_id,
      MAX(CASE WHEN event_type = 'Purchase' THEN 1 ELSE 0 END) AS has_purchase,  -- была хотя бы одна покупка
      MAX(CASE WHEN event_type = 'Checkout' THEN 1 ELSE 0 END) AS has_checkout  -- было хотя бы одно оформление
    FROM 
      customer_actions
    GROUP BY 
      customer_id
)

SELECT 
  COUNT(*) FILTER (WHERE has_purchase = 1) AS total_buyers,  -- всего покупателей
  COUNT(*) FILTER (WHERE has_purchase = 1 AND has_checkout = 0) AS buyers_no_checkout,  -- покупателей без этапа оформления
  COUNT(*) FILTER (WHERE has_purchase = 1 AND has_checkout = 1) AS buyers_with_checkout,  -- покупателей, кто прошел этап оформления хотя бы раз
  ROUND(100.0 * COUNT(*) FILTER (WHERE has_purchase = 1 AND has_checkout = 0) / COUNT(*) FILTER (WHERE has_purchase = 1), 2) AS share_no_checkout  -- доля покупателей без этапа оформления
FROM 
  events_by_user;

-- 14. Время первой покупки 'Purchase' до первого оформления 'Checkout'
WITH first_events_by_user AS (
    SELECT 
      customer_id,
      MIN(event_timestamp) FILTER (WHERE event_type = 'Purchase') AS first_purchase,  -- время первой покупки
      MIN(event_timestamp) FILTER (WHERE event_type = 'Checkout') AS first_checkout  -- время первого оформления
    FROM 
      customer_actions
    GROUP BY 
      customer_id
)

SELECT 
  COUNT(*) FILTER (WHERE first_purchase IS NOT NULL AND first_checkout IS NULL)  AS no_checkout, -- покупатели без этапа оформления
  COUNT(*) FILTER (WHERE first_purchase < first_checkout) AS buy_before_checkout,  -- первый заказ до оформления
  COUNT(*) FILTER (WHERE first_purchase > first_checkout) AS buy_after_checkout  -- первый заказ после оформления
FROM
  first_events_by_user;

-- 15. Событие 'Purchase' без предшествующего ему события 'Checkout'
SELECT 
  COUNT(*) AS purchase_no_checkout_before  -- считает количество событий
FROM 
  customer_actions purc
WHERE 
  purc.event_type = 'Purchase' -- где, событие покупки
  AND NOT EXISTS (  -- берет строки, которые не удовлетворяют условию
    SELECT 
      1
    FROM 
      customer_actions chk 
    WHERE 
      purc.customer_id = chk.customer_id  -- у одного пользователя 
      AND chk.event_type = 'Checkout'  -- с событием оформления
      AND purc.event_timestamp > chk.event_timestamp  -- событие оформления, раньше события покупки
);

-- 16. Пользователи с 'Purchase', но без 'Add to Cart'
WITH events_by_user AS (
    SELECT 
      customer_id,
      MAX(CASE WHEN event_type = 'Purchase' THEN 1 ELSE 0 END) AS has_purchase,  -- была покупка
      MAX(CASE WHEN event_type = 'Add to Cart' THEN 1 ELSE 0 END) AS has_cart  -- было добавление в корзину
    FROM 
      customer_actions
    GROUP BY 
      customer_id
)

SELECT 
  COUNT(*) FILTER (WHERE has_purchase = 1) AS total_buyers,  -- всего покупателей
  COUNT(*) FILTER (WHERE has_purchase = 1 AND has_cart = 0) AS buyers_no_cart,  -- покупателей без корзины
  ROUND(100.0 * COUNT(*) FILTER (WHERE has_purchase = 1 AND has_cart = 0) / COUNT(*) FILTER (WHERE has_purchase = 1), 2) AS share_no_cart  -- доля покупателей без корзины
FROM 
  events_by_user;

-- 17. Пользователи с 'Add to Cart', но без 'Page View'
WITH events_by_user AS (
    SELECT 
      customer_id,
      MAX(CASE WHEN event_type = 'Add to Cart' THEN 1 ELSE 0 END) AS has_cart,  -- было добавление в корзину
      MAX(CASE WHEN event_type = 'Page View' THEN 1 ELSE 0 END) AS has_view  -- был просмотр
    FROM 
      customer_actions
    GROUP BY 
      customer_id
)

SELECT 
  COUNT(*) FILTER (WHERE has_cart = 1) AS total_cart_users,  -- всего пользователей с корзиной
  COUNT(*) FILTER (WHERE has_cart = 1 AND has_view = 0) AS cart_users_no_view,  -- пользователей без просмотра
  ROUND(100.0 * COUNT(*) FILTER (WHERE has_cart = 1 AND has_view = 0) / COUNT(*) FILTER (WHERE has_cart = 1), 2) AS share_no_view  -- доля без просмотра
FROM 
  events_by_user;
