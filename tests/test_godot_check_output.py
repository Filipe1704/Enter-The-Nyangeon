import unittest
from godot_check_output import unexpected_errors


class GodotOutputChecks(unittest.TestCase):
    def test_native_signal_error_is_failure(self):
        self.assertTrue(unexpected_errors("UI_UX_RESULT checks=133 failures=0\nERROR: Object was freed during signal emission."))

    def test_ansi_native_error_is_failure(self):
        self.assertTrue(unexpected_errors("\x1b[31mERROR: Failed loading resource.\x1b[0m"))

    def test_script_error_is_failure(self):
        self.assertTrue(unexpected_errors("SCRIPT ERROR: Invalid call."))

    def test_only_exact_exit_count_is_allowed(self):
        self.assertFalse(unexpected_errors("ERROR: 1 resource still in use at exit (run with --verbose for details)."))
        self.assertTrue(unexpected_errors("ERROR: Parameter \"RenderingServer::get_singleton()\" is null."))
        self.assertTrue(unexpected_errors("ERROR: 1 resource still in use at exit: invalid state"))


if __name__ == "__main__":
    unittest.main()
