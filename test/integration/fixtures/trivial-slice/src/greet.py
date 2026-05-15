def greet(name):
    return f"Hello, {name}!"


def greet_loudly(name):
    return greet(name).upper()


if __name__ == "__main__":
    print(greet("world"))
    print(greet_loudly("world"))
