import tempfile
from pathlib import Path
import unittest
from check_localization import bare_quote, check


class LocalizationFormatChecks(unittest.TestCase):
    def test_godot_quote_loss_pattern_is_rejected(self):
        self.assertTrue(bare_quote('key,description of "brand",pt,vi\r\n'))

    def test_escaped_quotes_and_embedded_newline_are_allowed(self):
        self.assertFalse(bare_quote('key,"description of ""brand""\r\ncontinued",pt,vi\r\n'))

    def test_valid_utf8_bom_and_crlf(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.csv"
            path.write_bytes(b'\xef\xbb\xbf,zh_CN,en,pt,vi_VN\r\nkey,text,text,text,text\r\n')
            self.assertEqual(check(path), [])

    def test_missing_bom_lf_and_duplicate_key_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.csv"
            path.write_bytes(b',zh_CN,en,pt,vi_VN\nkey,text,text,text,text\nkey,text,text,text,text\n')
            self.assertGreaterEqual(len(check(path)), 3)


if __name__ == "__main__":
    unittest.main()
