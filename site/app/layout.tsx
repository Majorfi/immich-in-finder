import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { Analytics } from "@vercel/analytics/next";
import "./globals.css";

const geistSans = Geist({
  subsets: ["latin"],
  variable: "--font-geist-sans",
  display: "swap",
});

const geistMono = Geist_Mono({
  subsets: ["latin"],
  variable: "--font-geist-mono",
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL("https://findich.app"),
  title: "Findich — Mount your Immich library in the macOS Finder",
  description:
    "Mount your self-hosted Immich library in the macOS Finder. Albums, timeline, people and places become native folders, streamed on demand with drag-and-drop upload. Open source, pay what you want.",
  alternates: { canonical: "/" },
  keywords: [
    "Immich",
    "mount Immich in Finder",
    "macOS Finder",
    "Immich drive",
    "File Provider",
    "self-hosted photos",
    "Immich Mac app",
    "Immich Finder integration",
  ],
  openGraph: {
    title: "Findich — Mount your Immich library in the Finder",
    description:
      "Your self-hosted Immich library as a native folder in the macOS Finder. Like iCloud Drive, but for your own server.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Findich — Mount your Immich library in the Finder",
    description:
      "Your self-hosted Immich library as a native folder in the macOS Finder.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable}`}>
      <body>
        {children}
        <Analytics />
      </body>
    </html>
  );
}
