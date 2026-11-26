"""Project container syslog messages onto fixed fields before writing them."""

import json
import os
import re
import socket


MAX_PACKET_SIZE = 65_536
SITES = {"stuttgart_live_de": "stuttgart-live.de", "russ_live_de": "russ-live.de"}
ENVIRONMENTS = {"hetzner": "production", "staging": "staging"}
PROXY_SERVICES = {
    f"{app}-web-{destination}": {"site": site, "environment": environment}
    for app, site in SITES.items()
    for destination, environment in ENVIRONMENTS.items()
}
CONTAINER = re.compile(
    r"(stuttgart_live_de|russ_live_de)-(web|job)-(hetzner|staging)-[a-f0-9]{40}"
)
PRIORITY = re.compile(rb"<([0-9]{1,3})>1")
HTTP_METHODS = ("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
ROUTES = (
    "/", "/up", "/search", "/events/search_overlay", "/events/:id",
    "/passwords/*", "/backend/*", "/media/*", "/assets/*",
    "auth", "concerts", "contact",
)
OUTCOMES = ("successful", "failed", "locked")
ERROR_TYPES = (
    "ActiveRecord::RecordInvalid", "ActiveRecord::RecordNotFound", "ArgumentError",
    "LoadError", "NameError", "NoMethodError", "PG::ConnectionBad", "RuntimeError", "TypeError",
)


def bounded_timing(value, scale=1):
    if type(value) in (int, float) and 0 <= value <= 86_400_000 / scale:
        return round(value * scale, 3)
    return None


def valid_status(status):
    return type(status) is int and 100 <= status <= 599


def add_value(record, name, value):
    if value is not None:
        record[name] = value


def proxy_event(record):
    if record.get("msg") == "Request" and valid_status(record.get("status")):
        result = {"event": "proxy_access", "status": record["status"]}
        service = record.get("service")
        if isinstance(service, str):
            result.update(PROXY_SERVICES.get(service, {}))
        method = record.get("method")
        if method in HTTP_METHODS:
            result["method"] = method
        add_value(result, "duration_ms", bounded_timing(record.get("duration"), 1e-6))
        return result

    level = record.get("level")
    if level in ("WARN", "ERROR"):
        return {"event": "proxy_error", "level": level.lower()}
    return None


def app_event(record):
    event = record.get("event")
    if event == "login_attempt" and record.get("outcome") in OUTCOMES:
        return {"event": event, "outcome": record["outcome"]}
    if event == "application_error" and record.get("level") in ("warn", "error", "fatal"):
        error_type = record.get("error_class")
        return {
            "event": event, "level": record["level"],
            "error_class": error_type if error_type in ERROR_TYPES else "ApplicationError",
        }

    if event in ("proxy_timing", "request_timing") and valid_status(record.get("status")):
        route = record.get("route")
        result = {"route": route if route in ROUTES else "other", "status": record["status"]}
        if event == "proxy_timing":
            result["event"] = "nginx_access"
            add_value(result, "duration_ms", bounded_timing(record.get("request_s"), 1000))
        else:
            result["event"] = "application_request"
            add_value(result, "duration_ms", bounded_timing(record.get("app_ms")))
            add_value(result, "queue_ms", bounded_timing(record.get("queue_ms")))
        return result
    return None


def json_record(message):
    try:
        record = json.loads(message.removeprefix(b"\xef\xbb\xbf"))
    except (ValueError, RecursionError):
        return {}
    return record if isinstance(record, dict) else {}


def anonymize_packet(packet):
    if len(packet) > MAX_PACKET_SIZE:
        return None

    # Docker's RFC 5424 format has no structured data and uses APP-NAME for the tag.
    fields = packet.split(b" ", 7)
    if len(fields) != 8 or fields[6] != b"-":
        return None
    priority = PRIORITY.fullmatch(fields[0])
    if not priority or int(priority[1]) > 191:
        return None

    if fields[3] == b"kamal-proxy":
        identity = {"component": "kamal-proxy"}
        event = proxy_event(json_record(fields[7]))
    else:
        container = CONTAINER.fullmatch(fields[3].decode("ascii", errors="replace"))
        if not container:
            return None
        app, role, destination = container.groups()
        identity = {"site": SITES[app], "environment": ENVIRONMENTS[destination], "component": role}
        event = app_event(json_record(fields[7]))

    severity = int(priority[1]) % 8
    if event is None and severity <= 4:
        event = {"event": "process_error", "level": "warn" if severity == 4 else "error"}
    return {**identity, **event} if event is not None else None


def main():
    if os.getenv("LISTEN_PID") != str(os.getpid()) or os.getenv("LISTEN_FDS") != "1":
        return 2

    with socket.socket(fileno=3) as receiver:
        while True:
            event = anonymize_packet(receiver.recv(MAX_PACKET_SIZE + 1))
            if event is not None:
                print(json.dumps(event, separators=(",", ":")), flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
