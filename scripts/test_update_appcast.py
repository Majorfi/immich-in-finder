#!/usr/bin/env python3
# Tests for update_appcast.py. Runs the script and asserts the result with string
# checks (no XML parser, matching the script, so it runs on any python3).
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "update_appcast.py")
SKELETON = (
    "<?xml version='1.0' encoding='utf-8'?>\n"
    '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n'
    "  <channel>\n"
    "    <title>Findich</title>\n"
    "    <link>https://findich.app/appcast.xml</link>\n"
    "    <description>Updates.</description>\n"
    "    <language>en</language>\n"
    "  </channel>\n"
    "</rss>\n"
)


def run(path, version, url, sign, changelog):
    subprocess.run([sys.executable, SCRIPT, path, version, url, sign, changelog], check=True)
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def countVersion(text, version):
    return len(re.findall(
        r"<sparkle:shortVersionString>" + re.escape(version) + r"</sparkle:shortVersionString>",
        text,
    ))


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "appcast.xml")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(SKELETON)

        text = run(path, "1.2.0", "https://x/v1.2.0/Findich.dmg",
                   'sparkle:edSignature="SIG120==" length="111"', "- a first")
        check(countVersion(text, "1.2.0") == 1, "1.2.0 should be added once")
        check('sparkle:edSignature="SIG120=="' in text, "the signature should be present")
        check('url="https://x/v1.2.0/Findich.dmg"' in text, "the enclosure url should be present")
        check('length="111"' in text, "the length should be present")

        text = run(path, "1.2.0", "https://x/v1.2.0/Findich.dmg",
                   'sparkle:edSignature="SIG120==" length="111"', "- a first")
        check(countVersion(text, "1.2.0") == 1, "re-running the same version must stay idempotent")

        text = run(path, "1.2.1", "https://x/v1.2.1/Findich.dmg",
                   'sparkle:edSignature="SIG121==" length="222"', "- b second")
        check(countVersion(text, "1.2.0") == 1 and countVersion(text, "1.2.1") == 1, "both versions present")
        check(text.index("Findich 1.2.1") < text.index("Findich 1.2.0"), "the newest item must come first")

        text = run(path, "1.3.0", "https://x/v1.3.0/Findich.dmg",
                   'sparkle:edSignature="SIG130==" length="333"', "- fixed <a> & <b>")
        check("&lt;a&gt; &amp; &lt;b&gt;" in text, "commit text must be escaped")
        check("<![CDATA[<ul><li>" in text, "the description should be a CDATA HTML list")

        bad = subprocess.run([sys.executable, SCRIPT, path, "9.9.9", "https://x/Findich.dmg", "garbage", "- x"],
                             capture_output=True, text=True)
        check(bad.returncode != 0, "a malformed sign_update output should exit non-zero")
        check("unexpected sign_update output" in bad.stderr, "the failure should be explained")

    print("update_appcast: all tests passed")


main()
