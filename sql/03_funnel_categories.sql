-- ============================================================
-- Маркетплейс YouSell: воронка действий пользователя
-- Этап 3. Построение воронки по категориям
-- ============================================================
WITH view_cart_category AS (
    SELECT 
      p.product_category_name AS category, 
      ca.customer_id,
      MAX(CASE WHEN ca.event_type = 'Page View' THEN 1 ELSE 0 END) AS viewed,  -- просмотрели товар
      MAX(CASE WHEN ca.event_type = 'Add to Cart' THEN 1 ELSE 0 END) AS added  -- добавили товар
    FROM 
      customer_actions ca 
    LEFT JOIN products p USING(product_id)
    WHERE 
      ca.product_id IS NOT NULL  -- оставляем только строки, где указан id товара
    GROUP BY 
      p.product_category_name, ca.customer_id  -- группировка по паре категория-пользователь
),

purchase_category AS (
    SELECT DISTINCT  -- оставляем только уникальные значения по категории и пользователю
      p.product_category_name AS category, 
      ca.customer_id
    FROM
      customer_actions ca 
    LEFT JOIN order_items oi USING(order_id)
    LEFT JOIN products p ON p.product_id = oi.product_id  -- добавили состав заказа через join
    WHERE 
      ca.event_type = 'Purchase'  -- оставили только события покупки
),

total_info AS (  -- объединяем два CTE выше
    SELECT
      vcc.category,
      vcc.customer_id,
      vcc.viewed,
      vcc.added,
      MAX(CASE WHEN pc.customer_id IS NOT NULL THEN 1 ELSE 0 END) AS purchased  -- совершил покупку
    FROM 
      view_cart_category vcc
    LEFT JOIN purchase_category pc USING(customer_id, category)
    GROUP BY 
      vcc.category, vcc.customer_id, vcc.viewed, vcc.added
)

SELECT 
  category,
  COUNT(*) FILTER (WHERE viewed = 1) AS users_view,  --кол-во посмотревших товар
  COUNT(*) FILTER (WHERE added = 1) AS users_add,  -- кол-во добавивших товар в корзину
  COUNT(*) FILTER (WHERE purchased = 1) AS users_purchase,  -- кол-во совершивших покупку
  ROUND(100.0 * COUNT(*) FILTER (WHERE added = 1) / COUNT(*) FILTER (WHERE viewed = 1), 2) AS cr_view_add,  -- конверсия в добавление
  ROUND(100.0 * COUNT(*) FILTER (WHERE purchased = 1) / COUNT(*) FILTER (WHERE added = 1), 2) AS cr_add_purchase,  -- конверсия в покупку
  ROUND(100.0 * COUNT(*) FILTER (WHERE purchased = 1) / COUNT(*) FILTER (WHERE viewed = 1), 2) AS cr_view_purchase,  -- конверсия просмотр-покупка
  ROUND(100.0 - 100.0 * COUNT(*) FILTER (WHERE added = 1) / COUNT(*) FILTER (WHERE viewed = 1), 2) AS dropoff_view_add,  -- потеря на этапе добавление в корзину
  ROUND(100.0 - 100.0 * COUNT(*) FILTER (WHERE purchased = 1) / COUNT(*) FILTER (WHERE added = 1), 2) AS dropoff_add_purchase  -- потеря на этапе совершения покупки
FROM 
  total_info
GROUP BY 
  category 
ORDER BY 
  cr_view_purchase  -- порядок по сквозной конверсии
