from __future__ import annotations

import importlib
import sys
import types
import unittest


class _Document(types.SimpleNamespace):
    pass


class _FakeDatabase:
    def __init__(self, frappe_module):
        self._frappe = frappe_module
        self.sql_calls = []
        self.inject_concurrent_job_on_invoice_lock = False
        self.cancel_invoice_on_lock = False
        self._concurrent_job_injected = False

    def sql(self, query, values, as_dict=False):
        self.sql_calls.append((query, values, as_dict))
        if "`tabSales Invoice`" in query:
            if values != {"invoice_name": "SINV-0001"} or "FOR UPDATE" not in query:
                raise AssertionError((query, values))
            if self.cancel_invoice_on_lock:
                self._frappe.invoice.docstatus = 2
            if self.inject_concurrent_job_on_invoice_lock and not self._concurrent_job_injected:
                self._frappe.jobs.append(
                    _Document(
                        name="LOCAL-PRINT-JOB-CONCURRENT",
                        job_id="10000000-0000-4000-8000-000000000001",
                        status="Pending",
                        source_doctype="Sales Invoice",
                        source_name="SINV-0001",
                        ticket_type="Cashier",
                    )
                )
                self._concurrent_job_injected = True
            return [
                _Document(
                    name="SINV-0001",
                    docstatus=self._frappe.invoice.docstatus,
                    pos_profile=self._frappe.invoice.pos_profile,
                )
            ]
        if "`tabLocal Print Job`" in query:
            expected = {
                "source_doctype": "Sales Invoice",
                "source_name": "SINV-0001",
                "ticket_type": "Cashier",
            }
            if values != expected or "FOR UPDATE" not in query:
                raise AssertionError((query, values))
            matches = [
                _Document(name=job.name)
                for job in self._frappe.jobs
                if job.source_doctype == values["source_doctype"]
                and job.source_name == values["source_name"]
                and job.ticket_type == values["ticket_type"]
            ]
            return matches[:1]
        raise AssertionError(query)


class _FakeFrappe(types.ModuleType):
    class AuthenticationError(Exception):
        pass

    class PermissionError(Exception):
        pass

    class ValidationError(Exception):
        pass

    def __init__(self):
        super().__init__("frappe")
        self.session = types.SimpleNamespace(user="cashier@example.com")
        self.roles = ["Cashier"]
        self.settings = _Document(
            company="BCN Restaurant",
            pos_profile="Restaurant POS",
            selling_price_list="Restaurant Menu Price",
            default_currency="MMK",
            dine_in_customer_group="Dine In",
            takeaway_customer_group="Takeaway",
        )
        self.invoice = _Document(
            doctype="Sales Invoice",
            name="SINV-0001",
            docstatus=1,
            pos_profile="Restaurant POS",
        )
        self.invoice_reload_calls = 0
        self.get_doc_calls = 0

        def reload_invoice():
            self.invoice_reload_calls += 1
            return self.invoice

        self.invoice.reload = reload_invoice
        self.can_read = True
        self.pos_profile_can_read = True
        self.permission_checks = []
        self.config_queries = 0
        self.configs = [
            _Document(
                name="Cashier Printer",
                printer="Windows Cashier",
                print_format="Cashier Receipt",
                no_letterhead=1,
            )
        ]
        self.jobs = []
        self.print_calls = []
        self.job_calls = []
        self.status_calls = []
        self.retry_calls = []
        self.wakes = []
        self.logged_errors = []
        self.render_error = None
        self.job_error = None
        self.wake_error = None
        self.db = _FakeDatabase(self)

    def whitelist(self, methods=None):
        def decorate(function):
            function.allowed_http_methods = tuple(methods or ())
            return function

        return decorate

    def throw(self, message, exception=None):
        raise (exception or self.ValidationError)(message)

    def get_roles(self, user):
        return list(self.roles)

    def get_single(self, doctype):
        if doctype != "Restaurant Settings":
            raise AssertionError(doctype)
        return self.settings

    def get_doc(self, doctype, name):
        self.get_doc_calls += 1
        if (doctype, name) != ("Sales Invoice", self.invoice.name):
            raise AssertionError((doctype, name))
        return self.invoice

    def has_permission(self, doctype, ptype=None, doc=None):
        self.permission_checks.append((doctype, ptype, doc))
        if (doctype, ptype, doc) == ("Sales Invoice", "read", self.invoice):
            return self.can_read
        if (doctype, ptype, doc) == ("POS Profile", "read", "Restaurant POS"):
            return self.pos_profile_can_read
        raise AssertionError((doctype, ptype, doc))

    def get_all(self, doctype, **kwargs):
        if doctype != "Printer Item Group":
            raise AssertionError(doctype)
        self.config_queries += 1
        expected_filters = {
            "enabled": 1,
            "is_cashier": 1,
            "target_doctype": "Sales Invoice",
            "trigger_method": "manual",
            "pos_profile": "Restaurant POS",
        }
        if kwargs.get("filters") != expected_filters:
            raise AssertionError(kwargs.get("filters"))
        if kwargs.get("limit_page_length") != 2:
            raise AssertionError(kwargs.get("limit_page_length"))
        return list(self.configs)

    def get_print(self, doctype, name, **kwargs):
        self.print_calls.append((doctype, name, kwargs))
        if self.render_error:
            raise self.render_error
        return b"%PDF-sensitive-payload"

    def publish_realtime(self, event, message, **kwargs):
        self.wakes.append((event, message, kwargs))
        if self.wake_error:
            raise self.wake_error

    def log_error(self, message, title=None):
        self.logged_errors.append((message, title))


class PrintingApiTest(unittest.TestCase):
    def setUp(self):
        self.frappe = _FakeFrappe()
        local_printers = types.ModuleType("local_printers")
        local_printers_api = types.ModuleType("local_printers.api")
        local_printers_print_jobs = types.ModuleType("local_printers.api.print_jobs")
        local_printers_printing = types.ModuleType("local_printers.printing")
        local_printers_jobs = types.ModuleType("local_printers.printing.jobs")

        def create_print_job(**kwargs):
            self.frappe.job_calls.append(kwargs)
            if self.frappe.job_error:
                raise self.frappe.job_error
            job = _Document(
                name=f"LOCAL-PRINT-JOB-{len(self.frappe.jobs) + 1}",
                job_id=f"00000000-0000-4000-8000-{len(self.frappe.jobs) + 1:012d}",
                status="Pending",
                source_doctype=kwargs["source_doc"].doctype,
                source_name=kwargs["source_doc"].name,
                ticket_type=kwargs["ticket_type"],
            )
            self.frappe.jobs.append(job)
            return job

        def get_status(pos_profile):
            self.frappe.status_calls.append(pos_profile)
            return {
                "online": True,
                "last_seen": "2026-09-04 10:30:00",
                "pending": 2,
                "failed": 1,
            }

        def retry_failed(job_id):
            self.frappe.retry_calls.append(job_id)
            return {"status": "Pending"}

        local_printers_jobs.create_print_job = create_print_job
        local_printers_print_jobs.get_status = get_status
        local_printers_print_jobs.retry_failed = retry_failed

        sys.modules.update(
            {
                "frappe": self.frappe,
                "local_printers": local_printers,
                "local_printers.api": local_printers_api,
                "local_printers.api.print_jobs": local_printers_print_jobs,
                "local_printers.printing": local_printers_printing,
                "local_printers.printing.jobs": local_printers_jobs,
            }
        )
        sys.modules.pop("bcn_restaurant.api.common", None)
        sys.modules.pop("bcn_restaurant.api.printing", None)
        self.printing = importlib.import_module("bcn_restaurant.api.printing")

    def test_cashier_request_persists_submitted_accessible_invoice_then_wakes_with_metadata(self):
        result = self.printing.request_cashier_bill("SINV-0001")

        self.assertEqual(
            result,
            {
                "job_id": "00000000-0000-4000-8000-000000000001",
                "status": "Pending",
                "is_reprint": False,
            },
        )
        self.assertEqual(
            self.frappe.print_calls,
            [
                (
                    "Sales Invoice",
                    "SINV-0001",
                    {
                        "print_format": "Cashier Receipt",
                        "as_pdf": True,
                        "no_letterhead": 1,
                        "doc": self.frappe.invoice,
                    },
                )
            ],
        )
        job_call = self.frappe.job_calls[0]
        self.assertIs(job_call["source_doc"], self.frappe.invoice)
        self.assertEqual(job_call["printer"], "Windows Cashier")
        self.assertEqual(job_call["ticket_type"], "Cashier")
        self.assertEqual(job_call["print_format"], "Cashier Receipt")
        self.assertEqual(job_call["payload"], b"%PDF-sensitive-payload")
        self.assertEqual(job_call["no_letterhead"], True)
        self.assertNotIn("event_key", job_call)
        self.assertEqual(
            self.frappe.wakes,
            [
                (
                    "document_print_event",
                    {
                        "job_id": "00000000-0000-4000-8000-000000000001",
                        "pos_profile": "Restaurant POS",
                        "ticket_type": "Cashier",
                    },
                    {"after_commit": True},
                )
            ],
        )
        self.assertNotIn("%PDF", repr(self.frappe.wakes))
        self.assertEqual(self.frappe.invoice_reload_calls, 1)

    def test_repeat_requests_create_distinct_jobs_and_mark_only_later_request_reprint(self):
        first = self.printing.request_cashier_bill("SINV-0001")
        second = self.printing.request_cashier_bill("SINV-0001")

        self.assertFalse(first["is_reprint"])
        self.assertTrue(second["is_reprint"])
        self.assertNotEqual(first["job_id"], second["job_id"])
        self.assertNotIn("event_key", self.frappe.job_calls[0])
        self.assertNotIn("event_key", self.frappe.job_calls[1])

    def test_concurrent_request_uses_current_reads_and_marks_second_job_as_reprint(self):
        self.frappe.db.inject_concurrent_job_on_invoice_lock = True

        result = self.printing.request_cashier_bill("SINV-0001")

        self.assertTrue(result["is_reprint"])
        self.assertEqual(len(self.frappe.jobs), 2)
        self.assertEqual(len(self.frappe.db.sql_calls), 2)
        invoice_lock, prior_job_read = self.frappe.db.sql_calls
        self.assertIn("`tabSales Invoice`", invoice_lock[0])
        self.assertEqual(invoice_lock[1], {"invoice_name": "SINV-0001"})
        self.assertIn("FOR UPDATE", invoice_lock[0])
        self.assertIn("`tabLocal Print Job`", prior_job_read[0])
        self.assertEqual(
            prior_job_read[1],
            {
                "source_doctype": "Sales Invoice",
                "source_name": "SINV-0001",
                "ticket_type": "Cashier",
            },
        )
        self.assertIn("FOR UPDATE", prior_job_read[0])

    def test_cancel_committed_before_invoice_lock_prevents_render_job_and_wake(self):
        self.frappe.db.cancel_invoice_on_lock = True

        with self.assertRaises(self.frappe.ValidationError):
            self.printing.request_cashier_bill("SINV-0001")

        self.assertEqual(self.frappe.config_queries, 0)
        self.assertEqual(self.frappe.print_calls, [])
        self.assertEqual(self.frappe.job_calls, [])
        self.assertEqual(self.frappe.wakes, [])
        self.assertEqual(self.frappe.db.sql_calls[0][1], {"invoice_name": "SINV-0001"})
        self.assertIn("docstatus", self.frappe.db.sql_calls[0][0])
        self.assertIn("pos_profile", self.frappe.db.sql_calls[0][0])

    def test_draft_cancelled_and_inaccessible_invoices_create_no_job(self):
        cases = ((0, True), (2, True), (1, False))
        for docstatus, can_read in cases:
            with self.subTest(docstatus=docstatus, can_read=can_read):
                self.frappe.invoice.docstatus = docstatus
                self.frappe.can_read = can_read
                with self.assertRaises((self.frappe.PermissionError, self.frappe.ValidationError)):
                    self.printing.request_cashier_bill("SINV-0001")
                self.assertEqual(self.frappe.job_calls, [])
                self.assertEqual(self.frappe.wakes, [])

    def test_waiter_and_guest_cannot_request_cashier_printing(self):
        self.frappe.roles = ["Waiter"]
        with self.assertRaises(self.frappe.PermissionError):
            self.printing.request_cashier_bill("SINV-0001")
        self.frappe.session.user = "Guest"
        self.frappe.roles = []
        with self.assertRaises(self.frappe.AuthenticationError):
            self.printing.request_cashier_bill("SINV-0001")
        self.assertEqual(self.frappe.job_calls, [])

    def test_missing_or_ambiguous_cashier_configuration_creates_no_job(self):
        for configs in ([], self.frappe.configs * 2):
            with self.subTest(config_count=len(configs)):
                self.frappe.configs = configs
                with self.assertRaises(self.frappe.ValidationError) as raised:
                    self.printing.request_cashier_bill("SINV-0001")
                self.assertIn("cashier print configuration", str(raised.exception).lower())
                self.assertEqual(self.frappe.job_calls, [])
                self.assertEqual(self.frappe.wakes, [])

    def test_blank_print_format_delegates_to_frappe_default(self):
        self.frappe.configs[0].print_format = None

        result = self.printing.request_cashier_bill("SINV-0001")

        self.assertEqual(result["status"], "Pending")
        self.assertIsNone(self.frappe.print_calls[0][2]["print_format"])
        self.assertIsNone(self.frappe.job_calls[0]["print_format"])

    def test_invoice_must_match_current_pos_profile_and_use_canonical_name(self):
        self.frappe.invoice.pos_profile = "Other POS"
        with self.assertRaises(self.frappe.PermissionError):
            self.printing.request_cashier_bill("SINV-0001")
        self.frappe.invoice.pos_profile = "Restaurant POS"
        for invalid in (None, "", " SINV-0001", "SINV-0001\n", "x" * 141):
            with self.subTest(invalid=invalid):
                with self.assertRaises(self.frappe.ValidationError):
                    self.printing.request_cashier_bill(invalid)
        self.assertEqual(self.frappe.job_calls, [])

    def test_cashier_without_current_pos_profile_read_permission_creates_nothing(self):
        self.frappe.pos_profile_can_read = False

        with self.assertRaises(self.frappe.PermissionError):
            self.printing.request_cashier_bill("SINV-0001")

        self.assertEqual(self.frappe.config_queries, 0)
        self.assertEqual(self.frappe.print_calls, [])
        self.assertEqual(self.frappe.job_calls, [])
        self.assertEqual(self.frappe.wakes, [])

    def test_render_and_job_failures_do_not_publish_a_wake(self):
        self.frappe.render_error = RuntimeError("render failed")
        with self.assertRaises(RuntimeError):
            self.printing.request_cashier_bill("SINV-0001")
        self.assertEqual(self.frappe.job_calls, [])
        self.assertEqual(self.frappe.wakes, [])

        self.frappe.render_error = None
        self.frappe.job_error = RuntimeError("job failed")
        with self.assertRaises(RuntimeError):
            self.printing.request_cashier_bill("SINV-0001")
        self.assertEqual(self.frappe.wakes, [])

    def test_wake_failure_keeps_durable_acceptance_and_logs_no_payload(self):
        self.frappe.wake_error = RuntimeError("socket unavailable")
        result = self.printing.request_cashier_bill("SINV-0001")

        self.assertEqual(result["status"], "Pending")
        self.assertEqual(len(self.frappe.jobs), 1)
        self.assertEqual(len(self.frappe.logged_errors), 1)
        self.assertNotIn("%PDF", repr(self.frappe.logged_errors))

    def test_status_delegates_with_current_pos_profile_scope(self):
        result = self.printing.get_print_status()

        self.assertEqual(self.frappe.status_calls, ["Restaurant POS"])
        self.assertEqual(
            result,
            {
                "online": True,
                "last_seen": "2026-09-04 10:30:00",
                "pending": 2,
                "failed": 1,
            },
        )

    def test_status_allows_cashier_and_system_manager_but_denies_waiter_and_guest(self):
        self.assertTrue(self.printing.get_print_status()["online"])

        self.frappe.roles = ["System Manager"]
        self.assertTrue(self.printing.get_print_status()["online"])

        self.frappe.roles = ["Waiter"]
        with self.assertRaises(self.frappe.PermissionError):
            self.printing.get_print_status()

        self.frappe.session.user = "Guest"
        self.frappe.roles = []
        with self.assertRaises(self.frappe.AuthenticationError):
            self.printing.get_print_status()
        self.assertEqual(self.frappe.status_calls, ["Restaurant POS", "Restaurant POS"])

    def test_manager_retry_delegates_and_waiter_is_denied(self):
        self.frappe.roles = ["Restaurant Manager"]
        first_job_id = "72C86FB6-B90F-4572-A5E0-81A46F8BF599"
        self.assertEqual(
            self.printing.retry_print_job(first_job_id),
            {"status": "Pending"},
        )
        normalized_job_id = first_job_id.lower()
        self.assertEqual(self.frappe.retry_calls, [normalized_job_id])

        self.frappe.roles = ["Waiter"]
        with self.assertRaises(self.frappe.PermissionError):
            self.printing.retry_print_job("1bf4553c-4ee9-4fd3-afb6-ccbccb06f2b5")
        self.assertEqual(self.frappe.retry_calls, [normalized_job_id])

    def test_retry_rejects_non_uuid_job_id_before_delegating(self):
        self.frappe.roles = ["Restaurant Manager"]

        with self.assertRaises(self.frappe.ValidationError):
            self.printing.retry_print_job("not-a-job-uuid")

        self.assertEqual(self.frappe.retry_calls, [])

    def test_retry_allows_system_manager_but_denies_cashier_and_guest(self):
        job_id = "1bf4553c-4ee9-4fd3-afb6-ccbccb06f2b5"
        self.frappe.roles = ["System Manager"]
        self.assertEqual(self.printing.retry_print_job(job_id), {"status": "Pending"})

        self.frappe.roles = ["Cashier"]
        with self.assertRaises(self.frappe.PermissionError):
            self.printing.retry_print_job(job_id)

        self.frappe.session.user = "Guest"
        self.frappe.roles = []
        with self.assertRaises(self.frappe.AuthenticationError):
            self.printing.retry_print_job(job_id)

        self.assertEqual(self.frappe.retry_calls, [job_id])

    def test_mutation_endpoints_are_post_only(self):
        self.assertEqual(self.printing.request_cashier_bill.allowed_http_methods, ("POST",))
        self.assertEqual(self.printing.retry_print_job.allowed_http_methods, ("POST",))


if __name__ == "__main__":
    unittest.main()
