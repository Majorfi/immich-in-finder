# Security policy

Findich is a macOS client that talks only to the Immich server you point it at, using an API key you provide. It keeps that key in the macOS Keychain and sends nothing anywhere except to the server URL you configure.

## Reporting a vulnerability

Please report security issues privately rather than in a public issue. Use GitHub's private vulnerability reporting: open the **Security** tab of this repository and click **Report a vulnerability**, which starts a private advisory visible only to the maintainers.

Include what you found, how to reproduce it, and the impact. Expect an acknowledgement, then either a fix in a later release or an explanation of why it falls outside the scope below.

## Supported versions

Only the latest release is supported. Fixes ship in a new release rather than as patches to older ones.

## Scope

In scope: the container app and File Provider extension in this repository, including credential handling, the Immich API client, and the File Provider plumbing.

Out of scope: your Immich server itself (report those to the [Immich](https://github.com/immich-app/immich) project), and a server you have deliberately pointed Findich at, since the app trusts the server you configure.
