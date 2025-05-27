from faker import Faker
from typing import List, Tuple
import faker_commerce
from random import randint, choice
import locale

faker = Faker()
faker.add_provider(faker_commerce.Provider)


def get_customers(n=10) -> List[Tuple[str, str, str, str]]:
    return [(faker.first_name(), faker.last_name(), faker.email(), faker.phone_number()) for _ in range(n)]


def get_products(n=10) -> List[Tuple[str, str, float, int]]:
    return [(faker.ecommerce_name(), faker.text(max_nb_chars=50), round(randint(100, 9999) / 100, 2), randint(1, 20)) for _ in range(n)]


def create_sql_insert(table: str, columns: str, values: List[Tuple]) -> str:
    value_str = ",\n  ".join(
        f"({', '.join(repr(val) for val in row)})"
        for row in values
    )
    return f"INSERT INTO {table} ({columns}) VALUES\n  {value_str};"


def main():
    customers = get_customers(10)
    products = get_products(10)

    sql_customers = create_sql_insert(
        "customers", "first_name, last_name, email, phone", customers)
    sql_products = create_sql_insert(
        "products", "name, description, price, stock_quantity", products)

    print("-- Insertion dans la table customers")
    print(sql_customers)
    print("\n-- Insertion dans la table products")
    print(sql_products)


if __name__ == "__main__":
    main()
