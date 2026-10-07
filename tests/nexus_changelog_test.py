"""Regression tests for Nexus-friendly changelog publishing."""

import json
from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from scripts.nexus_changelog import format_for_nexus, nexus_changelog, release_body


METADATA = ROOT / "src/Enhanced Databank/modinfo.json"


class NexusChangelogTest(unittest.TestCase):
    def test_formats_current_release_as_plain_single_line_entries(self):
        changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
        version = json.loads(METADATA.read_text(encoding="utf-8"))["version"]
        body = release_body(changelog, version)

        rendered = nexus_changelog(changelog, version)

        self.assertEqual(
            len(rendered.splitlines()),
            len(re.findall(r"^- ", body, flags=re.MULTILINE)),
        )
        self.assertNotIn("###", rendered)
        self.assertNotIn("\n- ", rendered)
        self.assertNotIn("`", rendered)

    def test_preserves_categories_while_collapsing_wrapped_markdown(self):
        rendered = format_for_nexus(
            """### Added

- Added a `console` command with a
  wrapped description.

### Fixed

- Fixed the [button](https://example.com).
"""
        )

        self.assertEqual(
            rendered,
            "Added: Added a console command with a wrapped description.\n"
            "Fixed: Fixed the button.",
        )


if __name__ == "__main__":
    unittest.main()

