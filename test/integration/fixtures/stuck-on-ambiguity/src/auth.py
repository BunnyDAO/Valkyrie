"""Stub auth module — intentionally vague so the issue's AC is hard to interpret."""


def login(username, password):
    if not username or not password:
        return None
    return {"user": username, "token": "fake-token-" + username}


def logout(token):
    return True


def is_authenticated(token):
    return bool(token)
