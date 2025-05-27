from faker import Faker
from typing import List, Tuple
import faker_commerce
from random import randint, choice

faker = Faker()
faker.add_provider(faker_commerce.Provider)


def get_customers(n=10) -> List[Tuple[str, str, str, str]]:
    return [(faker.first_name(), faker.last_name(), faker.email(), faker.phone_number()) for _ in range(n)]


def get_products(n=10) -> List[Tuple[str, str, float, int]]:
    return [(faker.ecommerce_name(), faker.text(max_nb_chars=50), round(randint(100, 9999) / 100, 2), randint(1, 20)) for _ in range(n)]


def get_orders(n: int, customer_ids: List[int]) -> List[Tuple[int, str]]:
    return [(choice(customer_ids), 'pending') for _ in range(n)]


def get_order_items(order_ids: List[int], product_ids: List[int]) -> List[Tuple[int, int, int, float]]:
    items = []
    for order_id in order_ids:
        for _ in range(randint(1, 3)):
            product_id = choice(product_ids)
            quantity = randint(1, 5)
            unit_price = round(randint(500, 2000) / 100, 2)
            items.append((order_id, product_id, quantity, unit_price))
    return items


def get_payments(order_ids: List[int]) -> List[Tuple[int, float, str, str]]:
    methods = ['credit_card', 'paypal', 'bank_transfer']
    return [(order_id, round(randint(1000, 5000) / 100, 2), choice(methods), 'completed') for order_id in order_ids]


def get_shipments(order_ids: List[int]) -> List[Tuple[int, str, str]]:
    statuses = ['processing', 'shipped', 'delivered']
    return [(order_id, faker.address().replace("\n", ", "), choice(statuses)) for order_id in order_ids]


def create_sql_insert(table: str, columns: str, values: List[Tuple]) -> str:
    value_str = ",\n  ".join(
        f"({', '.join(repr(val) for val in row)})"
        for row in values
    )
    return f"INSERT INTO {table} ({columns}) VALUES\n  {value_str};"


def main():
    num_customers = 10
    num_products = 8
    num_orders = 15

    # Générer les données de base
    customers = get_customers(num_customers)
    products = get_products(num_products)

    # IDs simulés
    customer_ids = list(range(1, num_customers + 1))
    product_ids = list(range(1, num_products + 1))
    order_ids = list(range(1, num_orders + 1))

    orders = get_orders(num_orders, customer_ids)
    order_items = get_order_items(order_ids, product_ids)
    payments = get_payments(order_ids)
    shipments = get_shipments(order_ids)

    # Générer les requêtes SQL
    print("-- Insertion des clients")
    print(create_sql_insert("customers", "first_name, last_name, email, phone", customers))

    print("\n-- Insertion des produits")
    print(create_sql_insert("products", "name, description, price, stock_quantity", products))

    print("\n-- Insertion des commandes")
    print(create_sql_insert("orders", "customer_id, status", orders))

    print("\n-- Insertion des items de commande")
    print(create_sql_insert("order_items", "order_id, product_id, quantity, unit_price", order_items))

    print("\n-- Insertion des paiements")
    print(create_sql_insert("payments", "order_id, amount, method, status", payments))

    print("\n-- Insertion des livraisons")
    print(create_sql_insert("shipments", "order_id, delivery_address, status", shipments))


if __name__ == "__main__":
    main()