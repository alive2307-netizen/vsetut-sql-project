/* Проект «Разработка витрины и решение ad-hoc задач»
 * Цель проекта: подготовка витрины данных маркетплейса «ВсёТут»
 * и решение четырех ad hoc задач на её основе
 * 
 * Автор: Иващенко Александр
 * Дата: 13.01.2025
*/

/* Часть 1. Разработка витрины данных
 * Напишите ниже запрос для создания витрины данных
*/


/* Изменил тип объединения в итоговом запросе cost_correct с left join на join, получилось 62487 записей, как и в product_user_feature
 */


with review_correct as ( -- подзапрос по order_reviews, сгруппировал по order_id. здесь же поправка по оценкам
		select 
			order_id,
			AVG(correct_score) as avg_order_rating
		from (select 
				order_id, 
				case when review_score > 5 then review_score / 10
				else review_score  end as correct_score
				from ds_ecom.order_reviews) as stable_table
				group by order_id), 
	payments_data as ( -- здесь повозился, сделал подготовку данных для финального запроса
		select 
			distinct order_id,
			first_value(payment_type) over(partition by order_id order by payment_sequential) as first_payment,
			max(case when payment_type = 'промокод' then 1 else 0 end) over (partition by order_id) as promo_payment,  
			case when first_value(payment_type) over (partition by order_id order by payment_sequential) = 'денежный перевод' 
			then 1 else 0 end as money_transfer_payment,     
			case when max(payment_installments) over (partition by order_id) > 1 then 1 else 0 end as installment
			from ds_ecom.order_payments
			order by order_id),
	cost_correct as ( -- подзапрос по order_items. Здесь же вывел стоиость заказа (цена+доставка)
		select 
			itm.order_id,
			sum(itm.price) + sum(itm.delivery_cost) as one_order_cost
		from ds_ecom.order_items as itm
		join ds_ecom.orders as ord using (order_id) -- если правильно понял, то речь про объединение здесь
		where ord.order_status = 'Доставлено'
		group by order_id),
	 	orders_correct as ( -- подзапрос, где объединяю данные предыдущих подзапросов по order_id
	 		select 
	 			ord.order_id,
				ord.buyer_id,
				ord.order_purchase_ts,
				ord.order_status,
				revcor.avg_order_rating,
				payd.first_payment,
				payd.promo_payment,
				payd.money_transfer_payment,
				payd.installment,
				coscor.one_order_cost,
				case when ord.order_status = 'Отменено' then 1 else 0 end as cancelled_order
			from ds_ecom.orders as ord
			left join payments_data as payd using (order_id)
			left join cost_correct as coscor using (order_id)
			left join review_correct as revcor using (order_id)
			where ord.order_status in ('Доставлено', 'Отменено')
			)
	SELECT 
	   us.user_id, -- формирую итоговый запрос
       us.region,
       min(ordcor.order_purchase_ts) as first_order_ts,
       max(ordcor.order_purchase_ts) as last_order_ts,
       max(ordcor.order_purchase_ts) - min(ordcor.order_purchase_ts) as lifetime,
       count(ordcor.order_id) as total_orders,
       avg(ordcor.avg_order_rating)::numeric(10,2) as avg_order_rating,
       count(ordcor.order_id) filter (where ordcor.avg_order_rating is not null) as num_orders_with_rating,
       count(distinct case when ordcor.order_status = 'Отменено' then ordcor.order_id end) 
		as num_canceled_orders,
       round(100*count(distinct case when ordcor.order_status = 'Отменено' then ordcor.order_id end) * 1.0 / 
       nullif(count(distinct ordcor.order_id), 0), 2) || '%' as canceled_orders_ratio,
       sum(ordcor.one_order_cost) as total_order_costs,
       avg(ordcor.one_order_cost)::numeric(10,2) as avg_order_cost,
       sum(ordcor.installment) as num_installment_orders,
       sum(ordcor.promo_payment) as num_orders_with_promo,
       case when sum(ordcor.money_transfer_payment) > 0 then 1 else 0 end as used_money_transfer,
       case when sum(ordcor.installment) > 0 then 1 else 0 end as used_installments,
       max(case when ordcor.order_status = 'Отменено' then 1 else 0 end) as used_cancel
from ds_ecom.users as us
join orders_correct as ordcor using(buyer_id) -- изменил здесь
where region in (select us.region -- фильтрация по заданным условиям
				 from ds_ecom.orders as ord
				 join ds_ecom.users as us using(buyer_id)
				 where ord.order_status in ('Доставлено', 'Отменено')
				 group by us.region
				 order by count(ord.order_id) desc 
				 limit 3) 
group by user_id, region;


-- !!!Дальше ничего не менял!!!
/* Часть 2. Решение ad hoc задач
 * Для каждой задачи напишите отдельный запрос.
 * После каждой задачи оставьте краткий комментарий с выводами по полученным результатам.
*/

/* Задача 1. Сегментация пользователей 
 * Разделите пользователей на группы по количеству совершённых ими заказов.
 * Подсчитайте для каждой группы общее количество пользователей,
 * среднее количество заказов, среднюю стоимость заказа.
 * 
 * Выделите такие сегменты:
 * - 1 заказ — сегмент 1 заказ
 * - от 2 до 5 заказов — сегмент 2-5 заказов
 * - от 6 до 10 заказов — сегмент 6-10 заказов
 * - 11 и более заказов — сегмент 11 и более заказов
*/

-- Напишите ваш запрос тут
with users_segment as( -- подзапрос определения рейтинга клиента
	select 
		user_id, -- уникальный идентификатор клиента
		total_orders, -- общее количество заказов клиента 
		total_order_costs,
		avg_order_cost, -- средняя стоимость заказа клиента
		case 
        	when total_orders = 1 then '1 сегмент: 1 заказ'
        	when total_orders between 2 and 5 then '2 сегмент: 2-5 заказов'
        	when total_orders between 6 and 10 then '3 сегмент: 6-10 заказов'
       		when total_orders > 10 then '4 сегмент: 11 и более заказов'
       		ELSE 'Неизвестно' -- добавил
		end as segment -- сегмент клиента
	from ds_ecom.product_user_features
	)
select                     -- здесь внес правки. данные меняются, но незачительно
	segment, 
	count (DISTINCT user_id) as segment_users_count, -- общее число клиентов в сегменте (добавил DISTINCT)
	round(avg(total_orders), 2) as segment_avg_total_orders, -- среднее количество заказов в сегменте
	ROUND(SUM(total_order_costs)* 1.0 / NULLIF(SUM(total_orders), 0), 2) as segment_avg_order_cost -- средняя стоимость заказа в сегменте (поправил)
from users_segment
group by segment
order by segment;
/* Напишите краткий комментарий с выводами по результатам задачи 1.
 * 
 * Практически 97% пользователей входят в 1 сегмент, совершив на платформе 1 заказ. 
 * 3% входят во второй сегмент (2-5) заказов, со средним показателем в 2 заказа. 
 * Для 1-й категории средний показатель стоимость заказа составляет 3305 рублей, для второй — 3058 рублей — суммы одного порядка.
 * Для 3-4 категории средний чек постепенно снижается. То есть клиенты покупают чаще, но в среднем стоимость заказа — ниже.
 * Вместе с тем, для 3 и 4 категории выборка слишком низка — менее 0,01%.
*/

/* Задача 2. Ранжирование пользователей 
 * Отсортируйте пользователей, сделавших 3 заказа и более, по убыванию среднего чека покупки.  
 * Выведите 15 пользователей с самым большим средним чеком среди указанной группы.
*/

-- Напишите ваш запрос тут
select 
	user_id,
	total_orders,
	avg_order_cost,
	RANK() over (order by avg_order_cost DESC) as user_rank -- добавил ранжирование
from ds_ecom.product_user_features
where total_orders >= 3
order by avg_order_cost desc
limit 15; -- поправил
/* Напишите краткий комментарий с выводами по результатам задачи 2.
 * 
 * Среди пользователей, оформивших 3 и более заказов, выделяются первые 10 клиентов, 
 * у которых чек существенно выше среднего (более, чем в 2 раза). Начиная с 11 клиента, 
 * разница средних чеков в заказах все меньше.
 * В выборке преобладают клиенты, сделавшие по 3 заказа.
*/

/* Задача 3. Статистика по регионам. 
 * Для каждого региона подсчитайте:
 * - общее число клиентов и заказов;
 * - среднюю стоимость одного заказа;
 * - долю заказов, которые были куплены в рассрочку;
 * - долю заказов, которые были куплены с использованием промокодов;
 * - долю пользователей, совершивших отмену заказа хотя бы один раз.
*/

-- Напишите ваш запрос тут
select                             -- поправил расчет пользователей, совершивших отмену
	region,
	count(user_id) as total_users_region, -- общее число клиентов
	sum(total_orders) as total_orders_region, -- общее число заказов
	round(avg(avg_order_cost), 2) as avg_order_cost_region, -- средняя стоимость одного заказа
	round(100*sum(num_installment_orders)* 1.0 / nullif(sum(total_orders), 0), 2) || '%' 
	as percentage_orders_installments, -- доля заказов, купленных в рассрочку, %
	round(100*sum(num_orders_with_promo)* 1.0 / nullif(sum(total_orders), 0), 2) || '%' 
	as percentage_orders_promo, -- 	доля заказов, купленных с использованием промокодов, %
	ROUND(100*avg(used_cancel), 2)|| '%' as percentage_orders_canceled  -- доля пользователей, совершивших отмену заказа хотя бы один раз, %
from ds_ecom.product_user_features
group by region
order by total_users_region desc;
/* Напишите краткий комментарий с выводами по результатам задачи 3.
 * 
 * В топ-3 регионах по количеству клиентов преобладает Москва. 
 * В Москве насчитывается примерно в 3,3 раза больше клиентов, чем в Санкт-Петербурге и в 3,5 раза больше, чем в Новосибирской области.
 * Общее количество заказов значится приблизительно в тех же пропорциях.
 * Средний чек при этом самый крупный — в Санкт-Петербурге (3620 рублей). Незначительно меньше — в Новосибирской области (3519 рублей)
 * В Москве средний чек ниже, чем в Санкт-Петербурге на 12,5%. 
 * Вероятно, имеет место тенденция того, что с увеличением количества клиентов, снижается средний чек на заказ.
 * Около половины пользователей привыкли оформлять заказы в рассрочку.
 * В Москве реже других оформляют заказы в рассрочку (на 6,5-7%), чем в других регионах
 * В Санкт-Петербурге чаще других использую промокоды для покупок.
 * Процент отмененных заказов во всех регионах колеблется в пределах 0,41-0,61%, т.е. меньше статистической погрешности.
 * Чаще заказы отменяют в Москве. Реже — в Новосибирской области.
 * Корреляция количества использованных промокодов и суммы среднего чека может говорить о том, 
 * что более частое использование промокодов положительно сказывается на величине среднего чека
*/

/* Задача 4. Активность пользователей по первому месяцу заказа в 2023 году
 * Разбейте пользователей на группы в зависимости от того, в какой месяц 2023 года они совершили первый заказ.
 * Для каждой группы посчитайте:
 * - общее количество клиентов, число заказов и среднюю стоимость одного заказа;
 * - средний рейтинг заказа;
 * - долю пользователей, использующих денежные переводы при оплате;
 * - среднюю продолжительность активности пользователя.
*/

-- Напишите ваш запрос тут
SET lc_time = 'ru_RU';  -- изменил формат. пришлось помучаться, чтобы вышли нужные данные 
SELECT 
	TO_CHAR(month_orders, 'TMmon') AS order_month,  -- форматируем месяц
    count(distinct user_id) as total_users_per_month, -- общее количество клиентов
    sum(total_orders) as total_orders_per_month,-- общее количество заказов
    round(avg(avg_order_cost), 2) as average_order_cost, -- средняя стоимость одного заказа
    round(avg(avg_order_rating), 2) as average_rating,-- средний рейтинг заказа
    round(100*sum(used_money_transfer) * 1.0 / nullif(count(user_id), 0), 2) ||'%' 
    as money_transfer_ratio, -- доля пользователей с денежными переводами, %
    DATE_TRUNC('minute', AVG(lifetime)) AS average_lifetime -- средняя продолжительность активности пользователя
FROM (
	SELECT DATE_TRUNC('month', CAST(first_order_ts AS timestamp)) AS month_orders,*
	FROM ds_ecom.product_user_features
	WHERE EXTRACT(YEAR FROM CAST(first_order_ts AS timestamp)) = 2023) AS user_groups
group by 
    order_month
order by 
    order_month;
/* Напишите краткий комментарий с выводами по результатам задачи 4.
 *
 *  Активность пользователей по первому месяцу показывает положительную динаику привлечения новых клиентов.
 * С каждым месяцем на сайт приходило все больше клиентов. 
 * Отрицательная динамика проявляется в апреле, июне и декабре, но в мае показатель положительной динамики является существенно выше,
 * чем в другие месяцы. Возможно имеет место сбой в обработке входящих данных или какие-то другие факторы (сезонность, акции отдела
 * маркетинга и т.д.)
 * Показатель среднего чека изменяется от месяца к месяцу неравномерно:
 * в марте, апреле, июне, августе, сентябре фиксируется повышение среднего чека, в другие месяцы — падение. 
 * Динамику изменения цены можно охарактеризовать как не очень значительную.
 * С начала года и до сентября  включительно фиксируется положительная динамика положительных отзывов с периодическими незначительными падениями. 
 * В октябре наблюдается падение отметики на 0,07 единиц, а затем еще на 0,2 единицы — в ноябре. В декабре средняя отметка увеличивается на 0,08.
 * Динамика оплаты заказов денежными переводами не показывает какой-либо тенденции. 
 * В среднем, каждый пятый клиент из выборки оплачивал заказы денежным переводом.
 * Показатели продолжительности активности пользователя на сайте показывают снижение. Если в начале года это каоказатель составлял почти 13 дней, 
 * то в конце года этот показатель составил чуть более 2 дней.
 * Если учитывать количество заказов по месяцам и средний чек заказа, то можно говорить о том, 
 * что снижение количества времени пребывания на сайте не сказалось негативно на продажах сайта

