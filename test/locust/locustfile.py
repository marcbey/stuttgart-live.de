import random
from html.parser import HTMLParser
from urllib.parse import urlsplit

from locust import HttpUser, between, task


class DetailLinkParser(HTMLParser):
    def __init__(self, allowed_netlocs=None):
        super().__init__()
        self.allowed_netlocs = set(allowed_netlocs or [])
        self.event_paths = []
        self.news_paths = []

    def handle_starttag(self, tag, attrs):
        if tag != "a":
            return

        href = dict(attrs).get("href")
        if not href:
            return

        path = normalize_internal_path(href, self.allowed_netlocs)
        if not path:
            return

        if path.startswith("/events/") and path != "/events":
            if path not in self.event_paths:
                self.event_paths.append(path)
        elif path.startswith("/news/") and path != "/news":
            if path not in self.news_paths:
                self.news_paths.append(path)


def normalize_internal_path(href, allowed_netlocs=None):
    if not href or href.startswith("#"):
        return None

    parts = urlsplit(href)
    if parts.scheme and parts.scheme not in {"http", "https"}:
        return None

    allowed_netlocs = set(allowed_netlocs or [])
    if parts.netloc and parts.netloc not in allowed_netlocs:
        return None

    path = parts.path or "/"
    if not path.startswith("/"):
        return None

    if path.startswith("/backend"):
        return None

    return path


class StuttgartLiveUser(HttpUser):
    wait_time = between(1, 3)

    def on_start(self):
        self.event_detail_paths = []
        self.news_detail_paths = []
        self.allowed_netlocs = self._allowed_netlocs()
        self.discover_detail_paths()

    def discover_detail_paths(self):
        discovery_targets = [
            ("/", "DISCOVERY /"),
            ("/events", "DISCOVERY /events"),
            ("/news", "DISCOVERY /news"),
        ]

        for path, name in discovery_targets:
            response = self.client.get(path, name=name)
            if response.status_code >= 400:
                continue

            parser = DetailLinkParser(self.allowed_netlocs)
            parser.feed(response.text)

            self._merge_paths(self.event_detail_paths, parser.event_paths)
            self._merge_paths(self.news_detail_paths, parser.news_paths)

    @staticmethod
    def _merge_paths(target, candidates):
        for candidate in candidates:
            if candidate not in target:
                target.append(candidate)

    def _get_first_path(self, candidates):
        if not candidates:
            return None
        return random.choice(candidates)

    def _allowed_netlocs(self):
        allowed_netlocs = {
            urlsplit(self.host).netloc,
            "stuttgart-live.de",
            "www.stuttgart-live.de",
            "stuttgart-live.schopp3r.de",
            "localhost",
            "localhost:3000",
            "127.0.0.1",
            "127.0.0.1:3000",
        }
        return {netloc for netloc in allowed_netlocs if netloc}

    @task(5)
    def homepage(self):
        self.client.get("/", name="GET /")

    @task(3)
    def event_index(self):
        self.client.get("/events", name="GET /events")

    @task(2)
    def news_index(self):
        self.client.get("/news", name="GET /news")

    @task(4)
    def event_detail(self):
        path = self._get_first_path(self.event_detail_paths)
        if path is None:
            self.client.get("/events", name="GET /events (fallback)")
            return

        self.client.get(path, name="GET /events/:slug")

    @task(1)
    def news_detail(self):
        path = self._get_first_path(self.news_detail_paths)
        if path is None:
            self.client.get("/news", name="GET /news (fallback)")
            return

        self.client.get(path, name="GET /news/:slug")
