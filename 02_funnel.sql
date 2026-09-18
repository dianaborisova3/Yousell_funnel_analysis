-- ============================================================
-- Маркетплейс YouSell: воронка действий пользователя
-- Этап 2. Построение воронки: Page View - Add to Cart - Purchase
-- ============================================================
-- ВАЖНО: шаг Checkout исключён из воронки. Обоснование — в проверках 13–15
-- ============================================================
-- 1. Построение основной воронки
WITH user_steps AS (
    SELECT 
      customer_id,
      MAX(CASE WHEN event_type = 'Page View' THEN 1 ELSE 0 END) AS viewed,  -- просмотрел товар
      MAX(CASE WHEN event_type = 'Add to Cart' THEN 1 ELSE 0 END) AS added,  -- добавил в корзину
      MAX(CASE WHEN event_type = 'Purchase' THEN 1 ELSE 0 END) AS purchased  -- совершил покупку
    FROM 
      customer_actions
    GROUP BY 
      customer_id
),

funnel AS (
    SELECT 
      COUNT(*) FILTER (WHERE viewed = 1) AS users_view,  -- кол-во дошедших до просмотра
      COUNT(*) FILTER (WHERE added = 1) AS users_add,  -- кол-во добавивших в корзину
      COUNT(*) FILTER (WHERE purchased = 1) AS users_purchase  -- кол-во купивших
    FROM 
      user_steps
)

SELECT
  users_view,
  users_add,
  users_purchase,
  ROUND(100.0 * users_add / users_view, 2) AS cr_add_cart,  -- конверсия в добавление в корзину
  ROUND(100.0 * users_purchase / users_add, 2) AS cr_purchase,  -- конверсия в покупку
  ROUND(100.0 * users_purchase / users_view, 2) AS cr_view_purchase,  -- конверсия из просмотра в покупку
  ROUND(100.0 - 100.0 * users_add / users_view, 2) AS dropoff_view_cart,  -- потеря на шаге просмотр - добавление в корзину
  ROUND(100.0 - 100.0 * users_purchase / users_add, 2) AS dropoff_cart_purchase  -- потеря на шаге добавление в корзину - покупка
FROM 
  funnel;

-- 2. 'Checkout' как дополнительная метрика
WITH user_steps_2 AS (
    SELECT 
      customer_id,
      MAX(CASE WHEN event_type = 'Add to Cart' THEN 1 ELSE 0 END) AS added,  -- добавили в корзину
      MAX(CASE WHEN event_type = 'Checkout' THEN 1 ELSE 0 END) AS checked_out,  -- прошли оформление
      MAX(CASE WHEN event_type = 'Purchase' THEN 1 ELSE 0 END) AS purchased  -- совершили покупку
    FROM 
      customer_actions
    GROUP BY 
      customer_id
)

SELECT 
  COUNT(*) FILTER (WHERE added = 1) AS users_add,  -- кол-во добавивших товар
  COUNT(*) FILTER (WHERE checked_out = 1) AS users_checkout,  -- кол-во прошедших оформление
  COUNT(*) FILTER (WHERE checked_out = 1 AND purchased = 1) AS checkout_buyers,  -- чекаут и совершили покупку
  COUNT(*) FILTER (WHERE checked_out = 1 AND purchased = 0) AS checkout_leave,  -- чекаут и оставили корзину
  ROUND(100.0 * COUNT(*) FILTER (WHERE checked_out = 1 AND purchased = 1) / COUNT(*) FILTER (WHERE checked_out = 1), 2) AS cr_checkout_purchase  -- конверсия в покупку с шага чекаут
FROM 
  user_steps_2;