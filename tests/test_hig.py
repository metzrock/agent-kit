import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("fetch_hig", pathlib.Path(__file__).resolve().parents[1] / "modules/design/files/fetch_hig.py")
hig = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hig)


class HigTests(unittest.TestCase):
    def test_inline_and_blocks(self):
        nodes = [{"type": "strong", "inlineContent": [{"type": "text", "text": "Clarity"}]},
                 {"type": "reference", "identifier": "doc://com.apple.HIG/buttons#labels"}]
        self.assertEqual(hig.inline(nodes, {}), "**Clarity**[buttons#labels](buttons.md#labels)")
        self.assertIn("1. Read", hig.blocks([{"type": "orderedList", "items": [{"content": [
            {"type": "paragraph", "inlineContent": [{"type": "text", "text": "Read"}]}]}]}], {}))

    def test_retry_and_failure(self):
        with patch.object(hig.urllib.request, "urlopen", side_effect=OSError("offline")) as request, patch.object(hig.time, "sleep"):
            with self.assertRaises(OSError):
                hig.get("buttons")
            self.assertEqual(request.call_count, 3)

    def test_output_option_downloads_fresh_and_keeps_copyright(self):
        root = {"topicSections": [{"identifiers": ["doc://com.apple.HIG/buttons"]}]}
        page = {"metadata": {"title": "Buttons"}, "primaryContentSections": [{"content": [
            {"type": "paragraph", "inlineContent": [{"type": "text", "text": "Use clear labels."}]}]}],
            "legalNotices": {"copyright": "Copyright Apple Inc."}}
        with tempfile.TemporaryDirectory() as directory, patch.object(hig, "OUT", pathlib.Path(directory)), patch("sys.argv", ["fetch_hig.py", "--output", directory]), patch.object(hig, "get", side_effect=[root, page]) as get, patch.object(hig.time, "sleep"), patch("builtins.print"):
            hig.main()
            self.assertIn("Copyright Apple Inc.", (pathlib.Path(directory) / "buttons/buttons.md").read_text())
            self.assertIn("Buttons", (pathlib.Path(directory) / "INDEX.md").read_text())
            self.assertEqual(get.call_count, 2)


if __name__ == "__main__":
    unittest.main()
