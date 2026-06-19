import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://findich.app"),
  title: "Findich — an Immich drive for your macOS Finder",
  description:
    "Browse your self-hosted Immich library in the macOS Finder — albums, timeline, people and places as real folders, with on-demand download. Free & open source.",
  alternates: { canonical: "/" },
  keywords: [
    "Immich",
    "macOS Finder",
    "File Provider",
    "self-hosted photos",
    "Immich Mac app",
    "Immich Finder integration",
  ],
  openGraph: {
    title: "Findich — an Immich drive",
    description:
      "Your self-hosted Immich library as a native folder in the macOS Finder. Like iCloud Drive, but for your own server.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Findich — an Immich drive",
    description:
      "Your self-hosted Immich library as a native folder in the macOS Finder.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
