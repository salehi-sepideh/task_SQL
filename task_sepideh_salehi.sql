-- نمایش لیست سفارشات به همراه نسبت مبلغ سفارش به کل سفارشات هر کاربر
SELECT 
	orders.order_id ,
	orders.user_id,
	orders.total_amount AS order_amount,
	((orders.total_amount / user_totals.total_amount_user)*100) AS OrderPercentage

FROM orders
JOIN (SELECT orders.user_id, SUM(orders.total_amount) AS total_amount_user
		FROM orders
		WHERE order_status = 'complete' 
		GROUP BY orders.user_id) user_totals
ON orders.user_id = user_totals.user_id
WHERE order_status = 'complete' 

-- نمایش لیست محصولات به همراه نسبت تعداد موجودی محصول به کل موجودی محصولات آن دسته‌بندی
SELECT 
		products.product_id,
		products.category_id,
		products.`name`,
		products.stock_quantity,
		((products.stock_quantity / total_per_category.total_stock_per_category)*100) AS StockPercentage
FROM products
JOIN (SELECT 
				products.category_id,
				SUM(products.stock_quantity) AS total_stock_per_category
		FROM products
		GROUP BY category_id) total_per_category
ON products.category_id=total_per_category.category_id


--  نمایش لیست سفارشات به همراه مبلغ آخرین سفارش، اولین سفارش، سفارش قبلی و سفارش بعدی آن کاربر  

SELECT 
			orders.user_id,
			orders.order_id,
			orders.total_amount,
			payments.payment_method,
			payments.payment_status,
			payments.created_at,
			
-- مبلغ اولین سفارش

FIRST_VALUE(orders.total_amount)OVER(PARTITION BY orders.user_id ORDER BY orders.created_at ASC ) AS FirstPeymentTransaction,

-- مبلغ آخرین سفارش

LAST_VALUE(orders.total_amount)OVER(PARTITION BY orders.user_id ORDER BY orders.created_at ASC
ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastPeymentTransaction,
				
-- سفارش قبلی

LAG(orders.total_amount)OVER(PARTITION BY orders.user_id ORDER BY orders.created_at ASC ) AS PreviousPaymentTransaction,

-- سفارش بعدی

LEAD(orders.total_amount)OVER(PARTITION BY orders.user_id ORDER BY orders.created_at ASC ) AS NextPaymentTransaction
			
FROM orders
LEFT JOIN payments 
ON orders.order_id = payments.order_id
ORDER BY orders.user_id , orders.created_at ;


-- شناسایی محصولات پرفروش و کم‌فروش.

SELECT
		products.product_id AS ProductID,
		products.`name` AS ProductName,
		SUM(order_details.quantity) AS TotalSales,
		SUM(order_details.quantity * products.price) AS TotalRevenue,
		AVG(reviews.rating) AS AverageRating 
FROM products
LEFT JOIN order_details ON products.product_id=order_details.product_id
LEFT JOIN reviews ON products.product_id=reviews.product_id
GROUP BY products.product_id ;

-- شناسایی مشتریانی که بیشترین هزینه را صرف کرده‌اند، همراه با محبوب‌ترین دسته‌بندی محصولات خریداری‌شده آن‌ها.

WITH CategoryPurchases AS (
SELECT 
	orders.user_id AS CustomerID, 
	products.category_id AS CategoryID, 
	SUM(orders.total_amount) AS CategoryTotalSpent  
FROM orders 
JOIN order_details  ON orders.order_id = order_details.order_id
JOIN products  ON order_details.product_id = products.product_id
GROUP BY orders.user_id, products.category_id),

MostPopularCategory AS (
SELECT 
	CustomerID, 
	CategoryID, 
	CategoryTotalSpent,  
RANK() OVER (PARTITION BY CustomerID ORDER BY CategoryTotalSpent DESC) AS CategoryRank
FROM CategoryPurchases),

TotalSpent AS (
SELECT 
orders.user_id AS CustomerID, 
SUM(orders.total_amount) AS TotalSpent 
FROM orders 
GROUP BY orders.user_id)

SELECT 
	mp.CustomerID, 
	mp.CategoryID AS MostPopularCategory, 
	mp.CategoryTotalSpent AS Categorysum, 
	ts.TotalSpent
FROM MostPopularCategory mp
JOIN TotalSpent ts ON mp.CustomerID = ts.CustomerID
WHERE mp.CategoryRank = 1  
ORDER BY mp.CustomerID ASC;



-- تجمیع اطلاعات خرید و رفتار مشتری برای تحلیل بهتر.
-- من این سوال رو با کمک چت جی بی تی انجام دادم برام سخت بود

WITH CustomerBehavior AS (
SELECT 
      orders.user_id AS CustomerID,
      COUNT(orders.order_id) AS TotalOrders,  
      SUM(orders.total_amount) AS TotalSpent,  
      AVG(orders.total_amount) AS AverageOrderValue,  
      MAX(orders.created_at) AS LastOrderDate  
FROM orders
GROUP BY orders.user_id),

CategoryAndProductPurchases AS (
SELECT
   orders.user_id AS CustomerID,
   products.category_id AS CategoryID,
   products.product_id AS ProductID,
   COUNT(order_details.product_id) AS ProductCount
FROM orders
JOIN order_details ON orders.order_id = order_details.order_id
JOIN products ON order_details.product_id = products.product_id
GROUP BY orders.user_id, products.category_id, products.product_id),

MostPurchasedCategory AS (
SELECT
   CustomerID,
   CategoryID
FROM (
SELECT
   CustomerID,
   CategoryID,
ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY COUNT(ProductID) DESC) AS CategoryRank
FROM CategoryAndProductPurchases
GROUP BY CustomerID, CategoryID) AS RankedCategories
WHERE CategoryRank = 1),

MostPurchasedProduct AS (
SELECT
   CustomerID,
   ProductID
FROM (
SELECT
   CustomerID,
   ProductID,
ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY COUNT(ProductID) DESC) AS ProductRank
FROM CategoryAndProductPurchases
GROUP BY CustomerID, ProductID) AS RankedProducts
WHERE ProductRank = 1),

LoyalCustomers AS (
SELECT 
orders.user_id AS CustomerID,
CASE 
WHEN COUNT(orders.order_id) > 4 AND (DATEDIFF(CURDATE(), MAX(orders.created_at)) < 30) THEN 1
ELSE 0
END AS IsLoyalCustomer
FROM orders
GROUP BY orders.user_id)
SELECT 
    CustomerBehavior.CustomerID,
    CustomerBehavior.TotalOrders,
    CustomerBehavior.TotalSpent,
    CustomerBehavior.AverageOrderValue,
    CustomerBehavior.LastOrderDate,
    MostPurchasedCategory.CategoryID AS MostPurchasedCategory,
    MostPurchasedProduct.ProductID AS MostPurchasedProduct,
    LoyalCustomers.IsLoyalCustomer
FROM CustomerBehavior
JOIN MostPurchasedCategory ON CustomerBehavior.CustomerID = MostPurchasedCategory.CustomerID
JOIN MostPurchasedProduct ON CustomerBehavior.CustomerID = MostPurchasedProduct.CustomerID
JOIN LoyalCustomers ON CustomerBehavior.CustomerID = LoyalCustomers.CustomerID
ORDER BY CustomerBehavior.CustomerID;

