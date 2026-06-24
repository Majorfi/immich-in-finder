#!/usr/bin/env python3
# Insert (or replace) a Sparkle <item> at the top of the appcast channel.
# Usage: update_appcast.py <appcast.xml> <version> <dmg_url> <sign_update_output> <changelog>
import re
import sys
from email.utils import formatdate
from xml.etree import ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def sparkle(tag):
    return "{%s}%s" % (SPARKLE, tag)


appcast, version, dmgURL, signOutput, changelog = sys.argv[1:6]
signature = re.search(r'edSignature="([^"]+)"', signOutput).group(1)
length = re.search(r'length="([^"]+)"', signOutput).group(1)

tree = ET.parse(appcast)
channel = tree.getroot().find("channel")

# Idempotent: drop any existing item for this version before inserting.
for existing in channel.findall("item"):
    shortVersion = existing.find(sparkle("shortVersionString"))
    if shortVersion is not None and shortVersion.text == version:
        channel.remove(existing)

item = ET.Element("item")
ET.SubElement(item, "title").text = "Findich %s" % version
ET.SubElement(item, "pubDate").text = formatdate(localtime=False)
ET.SubElement(item, "description").text = changelog
ET.SubElement(item, sparkle("version")).text = version
ET.SubElement(item, sparkle("shortVersionString")).text = version
ET.SubElement(item, sparkle("minimumSystemVersion")).text = "13.0"
enclosure = ET.SubElement(item, "enclosure")
enclosure.set("url", dmgURL)
enclosure.set("length", length)
enclosure.set("type", "application/octet-stream")
enclosure.set(sparkle("edSignature"), signature)

# Newest item first, directly under <channel> ahead of any existing items.
items = channel.findall("item")
position = list(channel).index(items[0]) if items else len(list(channel))
channel.insert(position, item)

tree.write(appcast, encoding="utf-8", xml_declaration=True)
