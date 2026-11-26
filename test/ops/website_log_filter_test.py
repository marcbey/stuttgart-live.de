import importlib.util
import json
from pathlib import Path
import unittest


FILTER_PATH = (
    Path(__file__).resolve().parents[2]
    / "infra/ansible/roles/website_log_retention/files/website_log_filter.py"
)
spec = importlib.util.spec_from_file_location("website_log_filter", FILTER_PATH)
log_filter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(log_filter)

WEB = "stuttgart_live_de-web-hetzner-" + "a" * 40
JOB = "russ_live_de-job-staging-" + "b" * 40


def packet(tag, payload, priority=30):
    message = json.dumps(payload) if isinstance(payload, dict) else payload
    return f"<{priority}>1 2026-11-26T12:00:00.000000Z host {tag} 15 {tag} - {message}\n".encode()


class WebsiteLogFilterTest(unittest.TestCase):
    def test_kamal_request_is_rebuilt_without_request_identifiers(self):
        source = {
            "msg": "Request", "level": "INFO", "service": "russ_live_de-web-hetzner",
            "method": "GET", "status": 404, "duration": 12345000,
            "path": "/person/synthetic@example.invalid", "query": "token=secret",
            "host": "customer.example.invalid", "client_addr": "192.0.2.33",
            "remote_addr": "2001:db8::1", "request_id": "should-not-survive",
            "user_agent": "personal metadata",
        }

        self.assertEqual(log_filter.anonymize_packet(packet("kamal-proxy", source)), {
            "event": "proxy_access", "component": "kamal-proxy", "site": "russ-live.de",
            "environment": "production", "method": "GET", "status": 404,
            "duration_ms": 12.345,
        })

    def test_proxy_errors_keep_only_the_severity(self):
        error = {"level": "ERROR", "msg": "synthetic@example.invalid", "error": "192.0.2.33"}
        self.assertEqual(log_filter.anonymize_packet(packet("kamal-proxy", error)), {
            "component": "kamal-proxy", "event": "proxy_error", "level": "error",
        })

    def test_nginx_projects_only_known_routes_and_bounded_numbers(self):
        source = {
            "event": "proxy_timing", "route": "/people/synthetic@example.invalid",
            "status": 200, "request_s": 0.123, "request_id": "unique-id",
            "upstream_s": "192.0.2.33", "email": "synthetic@example.invalid",
        }
        self.assertEqual(log_filter.anonymize_packet(packet(WEB, source)), {
            "site": "stuttgart-live.de", "environment": "production", "component": "web",
            "event": "nginx_access", "route": "other", "status": 200, "duration_ms": 123.0,
        })

    def test_rails_login_and_failed_job_records_never_copy_raw_fields(self):
        login = {"event": "login_attempt", "outcome": "failed", "email": "synthetic@example.invalid"}
        error = {"event": "application_error", "level": "error", "error_class": "ArgumentError",
                 "message": "synthetic@example.invalid", "backtrace": ["includes 192.0.2.33"]}
        self.assertEqual(log_filter.anonymize_packet(packet(WEB, login)), {
            "site": "stuttgart-live.de", "environment": "production", "component": "web",
            "event": "login_attempt", "outcome": "failed",
        })
        self.assertEqual(log_filter.anonymize_packet(packet(JOB, error)), {
            "site": "russ-live.de", "environment": "staging", "component": "job",
            "event": "application_error", "level": "error", "error_class": "ArgumentError",
        })

    def test_plain_text_is_discarded_or_projected_to_a_fixed_error_event(self):
        raw = "runtime error for 192.0.2.33 and synthetic@example.invalid"
        self.assertIsNone(log_filter.anonymize_packet(packet(WEB, raw)))
        self.assertIsNone(log_filter.anonymize_packet(packet("other-app", raw, priority=27)))
        self.assertEqual(log_filter.anonymize_packet(packet(WEB, raw, priority=27)), {
            "site": "stuttgart-live.de", "environment": "production", "component": "web",
            "event": "process_error", "level": "error",
        })
        self.assertIsNone(log_filter.anonymize_packet(b"invalid header with a secret"))

    def test_unexpected_metadata_and_invalid_numbers_are_ignored(self):
        source = {"msg": "Request", "status": 200, "service": ["synthetic@example.invalid"],
                  "method": "synthetic@example.invalid", "duration": float("inf")}
        self.assertEqual(log_filter.anonymize_packet(packet("kamal-proxy", source)), {
            "component": "kamal-proxy", "event": "proxy_access", "status": 200,
        })


if __name__ == "__main__":
    unittest.main()
