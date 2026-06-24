#!/usr/bin/env python3
# Insert (or replace) a Sparkle <item> at the top of the appcast channel.
# Pure string templating with no XML parser, so it does not depend on pyexpat,
# which is broken on some Homebrew Python builds.
# Usage: update_appcast.py <appcast.xml> <version> <dmg_url> <sign_update_output> <changelog>
import re
import sys
from email.utils import formatdate


def escape(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def htmlNotes(changelog):
    # Render the "- sha message" changelog as an HTML list inside CDATA, so Sparkle
    # shows it formatted in the update dialog. escape() neutralises markup in commit
    # messages and, since it turns ">" into "&gt;", also prevents a stray "]]>".
    lines = [line[2:] for line in changelog.splitlines() if line.startswith("- ")]
    if lines:
        inner = "<ul>" + "".join("<li>%s</li>" % escape(line) for line in lines) + "</ul>"
    else:
        inner = escape(changelog.strip())
    return "<![CDATA[%s]]>" % inner


appcast, version, dmgURL, signOutput, changelog = sys.argv[1:6]
signatureMatch = re.search(r'edSignature="([^"]+)"', signOutput)
lengthMatch = re.search(r'length="([^"]+)"', signOutput)
if signatureMatch is None or lengthMatch is None:
    sys.exit("update_appcast: unexpected sign_update output: %r" % signOutput)
signature = signatureMatch.group(1)
length = lengthMatch.group(1)

with open(appcast, encoding="utf-8") as handle:
    text = handle.read()

# Idempotent: drop any existing <item> for this version (matched within one item).
within = r"(?:(?!</item>)[\s\S])*?"
text = re.sub(
    r"[ \t]*<item>" + within
    + r"<sparkle:shortVersionString>" + re.escape(version) + r"</sparkle:shortVersionString>"
    + within + r"</item>\n?",
    "",
    text,
)

item = (
    "    <item>\n"
    "      <title>Findich {v}</title>\n"
    "      <pubDate>{date}</pubDate>\n"
    "      <description>{notes}</description>\n"
    "      <sparkle:version>{v}</sparkle:version>\n"
    "      <sparkle:shortVersionString>{v}</sparkle:shortVersionString>\n"
    "      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>\n"
    '      <enclosure url="{url}" length="{length}" type="application/octet-stream" sparkle:edSignature="{sig}"/>\n'
    "    </item>\n"
).format(
    v=escape(version),
    date=formatdate(localtime=False),
    notes=htmlNotes(changelog),
    url=escape(dmgURL),
    length=length,
    sig=signature,
)

# Newest first: insert right after the channel metadata.
anchor = "</language>\n"
cut = text.index(anchor) + len(anchor)
text = text[:cut] + item + text[cut:]

with open(appcast, "w", encoding="utf-8") as handle:
    handle.write(text)
