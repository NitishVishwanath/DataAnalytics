--Q1: Import the dataset and do usual exploratory analysis steps like checking the structure & characteristics of the dataset:
--Q1.1: Data type of all columns in the "customers" table.

SELECT column_name, data_type
FROM `target`.INFORMATION_SCHEMA.COLUMNS
WHERE table_name = 'customers';

--Q1.2: Get the time range between which the orders were placed.

SELECT
MIN(order_purchase_timestamp) AS frist_order_date,
MAX(order_purchase_timestamp) AS last_order_date
FROM `target.orders`;

--Q1.3: Count the number of Cities and States in our dataset.

with all_city_state as 
(
SELECT 
geolocation_city AS city,
geolocation_state AS state
FROM `target.geolocation`

UNION DISTINCT

SELECT 
customer_city AS city,
customer_state AS state
FROM `target.customers` 

UNION DISTINCT

SELECT
seller_city AS city,
seller_state AS state 
FROM `target.sellers`
)

SELECT
COUNT(DISTINCT city) as total_no_of_cities,
COUNT(DISTINCT state) as total_no_of_states
FROM all_city_state;


--Q2: In-depth Exploration:
--Q2.1: Is there a growing trend in the no. of orders placed over the past years?

WITH order_growth_year AS
(
SELECT
EXTRACT(year FROM order_purchase_timestamp) AS order_year,
COUNT(order_id) AS no_of_orders,
LAG(COUNT(order_id)) OVER(ORDER BY COUNT(order_id)) AS next_year_order_count
FROM `target.orders`
GROUP BY order_year
ORDER BY 1
)

SELECT
order_year,
no_of_orders,
ROUND(((no_of_orders - next_year_order_count)/next_year_order_count)*100,2) AS growth_percentage_year
FROM order_growth_year
ORDER BY 1;

-------------------------------------------------------------------------------------------------
WITH order_growth_month_lag AS
(
SELECT
*,
SUM(no_of_orders) OVER(ORDER BY order_year_month) AS gradually_increating_total_order_per_year_month,
LAG(no_of_orders) OVER(ORDER BY order_year_month) AS next_month_order_count
FROM
(
SELECT 
FORMAT_TIMESTAMP('%Y-%m', order_purchase_timestamp) AS order_year_month,
COUNT(order_id) AS no_of_orders,
FROM `target.orders`
GROUP BY order_year_month
ORDER BY 1,2
) AS order_growth_month
ORDER BY 1,2
)

SELECT
order_year_month,
no_of_orders,
ROUND(((no_of_orders - next_month_order_count)/next_month_order_count)*100,2) AS growth_percentage_per_month,
gradually_increating_total_order_per_year_month,
FROM order_growth_month_lag
ORDER BY 1,2;

--Q2.2: Can we see some kind of monthly seasonality in terms of the no. of orders being placed?


WITH order_growth_month_lag AS
(
SELECT
*,
LAG(no_of_orders) OVER(ORDER BY order_year_month) AS next_month_order_count
FROM
(
SELECT
FORMAT_TIMESTAMP('%Y-%m', order_purchase_timestamp) AS order_year_month,
EXTRACT(year FROM order_purchase_timestamp) AS order_year,
EXTRACT(month FROM order_purchase_timestamp) AS order_months,
COUNT(order_id) AS no_of_orders
FROM `target.orders`
GROUP BY order_year_month, order_year, order_months
ORDER BY 1,2
) AS order_growth_month
ORDER BY 1,2
)

SELECT
order_year_month,
no_of_orders,
ROUND(((no_of_orders - next_month_order_count)/next_month_order_count)*100,2) AS growth_percentage,
FIRST_VALUE(order_months) OVER(PARTITION BY order_year ORDER BY no_of_orders DESC) AS peak_month
FROM order_growth_month_lag
ORDER BY 1,2;



--Q2.3: During what time of the day, do the Brazilian customers mostly place their orders? (Dawn, Morning, Afternoon or Night)
--	0-6 hrs : Dawn
--	7-12 hrs : Mornings
--	13-18 hrs : Afternoon
--	19-23 hrs : Night

WITH order_time_of_day AS
(
SELECT 
CASE
  WHEN EXTRACT(hour FROM order_purchase_timestamp) BETWEEN 00 AND 06
  THEN 'Dawn'
  WHEN EXTRACT(hour FROM order_purchase_timestamp) BETWEEN 07 AND 12
  THEN 'Mornings'
  WHEN EXTRACT(hour FROM order_purchase_timestamp) BETWEEN 13 AND 18
  THEN 'Afternoon'
  WHEN EXTRACT(hour FROM order_purchase_timestamp) BETWEEN 19 AND 23
  THEN 'Night'
END AS time_of_day,
COUNT(order_id) no_of_orders
FROM `target.orders`
GROUP BY time_of_day
ORDER BY 2 DESC
)

SELECT
time_of_day,
no_of_orders,
CONCAT(
  (SELECT time_of_day,
  FROM order_time_of_day
  WHERE no_of_orders = (
  SELECT
  MAX(no_of_orders)
  FROM order_time_of_day
  )),', n/o orders: ',MAX(no_of_orders) OVER()
      ) AS most_orders_time
  FROM order_time_of_day
  ORDER BY 2 DESC;


--Q3: Evolution of E-commerce orders in the Brazil region:
--Q3.1: Get the month on month no. of orders placed in each state.

SELECT c.customer_state,
FORMAT_TIMESTAMP('%Y-%m', order_purchase_timestamp) AS order_year_month,
COUNT(o.order_id) no_of_orders
FROM `target.customers` c
INNER JOIN `target.orders` o
ON c.customer_id = o.customer_id
GROUP BY c.customer_state, order_year_month 
ORDER BY 1,2,3;


--Q3.2: How are the customers distributed across all the states?

SELECT customer_state,
COUNT(DISTINCT customer_id) no_of_customers
FROM `target.customers`
GROUP BY customer_state
ORDER BY 1;

--Q4: Impact on Economy: Analyze the money movement by e-commerce by looking at order prices, freight and others.	
--Q4.1: Get the % increase in the cost of orders from year 2017 to 2018 (include months between Jan to Aug only).
--You can use the "payment_value" column in the payments table to get the cost of orders.

WITH order_cost_year_month AS
(
SELECT *,
LAG(total_order_value) OVER(ORDER BY order_year) next_month_total_order_value
FROM
(
SELECT
EXTRACT(year FROM o.order_purchase_timestamp) order_year,
ROUND(SUM(p.payment_value),2) total_order_value,
FROM `target.orders` o
INNER JOIN `target.payments` p
ON o.order_id = p.order_id
WHERE (EXTRACT(year FROM o.order_purchase_timestamp) BETWEEN 2017 AND 2018) AND
(EXTRACT(month FROM o.order_purchase_timestamp) BETWEEN 1 AND 8)
GROUP By order_year
ORDER BY 1,2
)
ORDER BY order_year
)

SELECT
order_year order_jan_aug_year,
total_order_value,
ROUND(((total_order_value - next_month_total_order_value)/next_month_total_order_value)*100,2) growth_percentage
FROM order_cost_year_month
ORDER BY 1,2,3;


--Q4.2: Calculate the Total & Average value of order price for each state.

SELECT
c.customer_state,
ROUND(SUM(p.payment_value),2) total_order_vlaue,
ROUND(AVG(p.payment_value),2) Average_order_vlaue,
FROM
`target.customers` c
INNER JOIN `target.orders` o
ON c.customer_id = o.customer_id
INNER JOIN `target.payments` p
ON o.order_id = p.order_id
GROUP BY c.customer_state
ORDER BY 1;


--Q4.3: Calculate the Total & Average value of order freight for each state.


SELECT
c.customer_state,
ROUND(SUM(ot.freight_value),2) total_freight_vlaue,
ROUND(AVG(ot.freight_value),2) Average_freight_vlaue,
FROM
`target.customers` c
INNER JOIN `target.orders` o
ON c.customer_id = o.customer_id
INNER JOIN `target.order_items`ot
ON o.order_id = ot.order_id
GROUP BY c.customer_state
ORDER BY 1;


--Q5: Analysis based on sales, freight and delivery time.

--Q5.1: Find the no. of days taken to deliver each order from the order’s purchase date as delivery time.
--Also, calculate the difference (in days) between the estimated & actual delivery date of an order.
--Do this in a single query.
--You can calculate the delivery time and the difference between the estimated & actual delivery date using the given formula:
--	time_to_deliver = order_delivered_customer_date - order_purchase_timestamp
--	diff_estimated_delivery = order_estimated_delivery_date - order_delivered_customer_date

SELECT
order_id,
order_purchase_timestamp,
order_estimated_delivery_date,
order_delivered_customer_date,
DATE_DIFF(order_delivered_customer_date, order_purchase_timestamp, day) time_to_deliver,
DATE_DIFF(order_estimated_delivery_date, order_delivered_customer_date, day) diff_estimated_delivery,
FROM
`target.orders`
WHERE LOWER(order_status) = 'delivered'
ORDER BY 2;


--Q5.2: Find out the top 5 states with the highest & lowest average freight value.

WITH low_average_freight_vlaue AS
(SELECT *
FROM
(
SELECT *,
DENSE_RANK() OVER(ORDER BY lowest_average_freight_vlaue) as denserank,
ROW_NUMBER() OVER(ORDER BY lowest_average_freight_vlaue) as row_num
FROM
(
SELECT
c.customer_state,
ROUND(AVG(ot.freight_value),2) lowest_average_freight_vlaue
FROM
`target.customers` c
INNER JOIN `target.orders` o
ON c.customer_id = o.customer_id
INNER JOIN `target.order_items`ot
ON o.order_id = ot.order_id
GROUP BY c.customer_state
ORDER BY 2 DESC
)
ORDER BY lowest_average_freight_vlaue 
) WHERE denserank <= 5
)

,

 high_average_freight_vlaue AS
(
  SELECT *
FROM
(
SELECT *,
DENSE_RANK() OVER(ORDER BY highest_average_freight_vlaue DESC) as denserank,
ROW_NUMBER() OVER(ORDER BY highest_average_freight_vlaue DESC) as row_num
FROM
(
SELECT
c.customer_state,
ROUND(AVG(ot.freight_value),2) highest_average_freight_vlaue
FROM
`target.customers` c
INNER JOIN `target.orders` o
ON c.customer_id = o.customer_id
INNER JOIN `target.order_items`ot
ON o.order_id = ot.order_id
GROUP BY c.customer_state
ORDER BY 2 DESC
)
ORDER BY highest_average_freight_vlaue DESC
) WHERE denserank <= 5
)

SELECT
h.customer_state AS high_avg_state,
h.highest_average_freight_vlaue,
l.customer_state AS low_avg_state,
l.lowest_average_freight_vlaue
FROM
low_average_freight_vlaue AS l
INNER JOIN high_average_freight_vlaue AS h
ON l.row_num = h.row_num
ORDER BY 2 DESC;


--Q5.3: Find out the top 5 states with the highest & lowest average delivery time.


WITH low_average_delivery AS
(SELECT *
FROM
(
SELECT *,
DENSE_RANK() OVER(ORDER BY lowest_average_delivery) as denserank,
ROW_NUMBER() OVER(ORDER BY lowest_average_delivery) as row_num
FROM
(
SELECT
c.customer_state,
ROUND(AVG(DATE_DIFF(o.order_delivered_customer_date, o.order_purchase_timestamp, day)),2) lowest_average_delivery,
FROM
`target.customers` c
INNER JOIN `target.orders` o
ON c.customer_id = o.customer_id
GROUP BY c.customer_state
ORDER BY 2 DESC
)
ORDER BY lowest_average_delivery 
) WHERE denserank <= 5
)

,
 high_average_delivery AS
(
  SELECT *
FROM
(
SELECT *,
DENSE_RANK() OVER(ORDER BY highest_average_delivery DESC) as denserank,
ROW_NUMBER() OVER(ORDER BY highest_average_delivery DESC) as row_num
FROM
(
SELECT
c.customer_state,
ROUND(AVG(DATE_DIFF(o.order_delivered_customer_date, o.order_purchase_timestamp, day)),2) highest_average_delivery,
FROM
`target.customers` c
INNER JOIN `target.orders` o
ON c.customer_id = o.customer_id
GROUP BY c.customer_state
ORDER BY 2 DESC
)
ORDER BY highest_average_delivery DESC
) WHERE denserank <= 5
)


SELECT
h.customer_state AS high_avg_state,
h.highest_average_delivery,
l.customer_state AS low_avg_state,
l.lowest_average_delivery
FROM low_average_delivery AS l
INNER JOIN high_average_delivery AS h
ON l.row_num = h.row_num
ORDER BY 2 DESC;


--Q5.4: Find out the top 5 states where the order delivery is really fast as compared to the estimated date of delivery.
--You can use the difference between the averages of actual & estimated delivery date to figure out how fast the delivery was for each state.


WITH state_average_delivery AS
(
SELECT
c.customer_state,
ROUND(AVG(DATE_DIFF(o.order_estimated_delivery_date, o.order_delivered_customer_date, day)),2) average_delivery,
FROM
`target.customers` c
INNER JOIN `target.orders` o
ON c.customer_id = o.customer_id
WHERE LOWER(o.order_status) = 'delivered'
GROUP BY c.customer_state
ORDER BY 2 DESC
)
,
 
 drank AS
(
SELECT *,
DENSE_RANK() OVER(ORDER BY average_delivery DESC) as denserank,
FROM state_average_delivery
ORDER BY average_delivery DESC
)
  
SELECT
customer_state,
average_delivery as avg_days_fast_delivery
FROM drank
WHERE denserank <= 5;


--Q6: Analysis based on the payments:
--Q6.1: Find the month on month no. of orders placed using different payment types.

SELECT 
FORMAT_TIMESTAMP('%Y-%m', o.order_purchase_timestamp) AS order_year_month,
p.payment_type,
COUNT(DISTINCT o.order_id) no_of_orders
FROM
`target.customers` c
INNER JOIN `target.orders` o
ON c.customer_id = o.customer_id
INNER JOIN `target.payments` p
On p.order_id = o.order_id
GROUP BY order_year_month, p.payment_type
ORDER BY 1,2,3;


--Q6.2: Find the no. of orders placed on the basis of the payment installments that have been paid.

SELECT
payment_installments,
COUNT(DISTINCT order_id) no_of_orders
FROM `target.payments`
WHERE payment_installments != 0
GROUP BY payment_installments
ORDER BY 1,2;