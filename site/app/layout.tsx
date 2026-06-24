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
  title: "Findich: an Immich drive for your macOS Finder",
  description:
    "Browse your self-hosted Immich library in the macOS Finder. Albums, timeline, people and places become real folders, with on-demand download. Open source, pay what you want.",
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
    title: "Findich: an Immich drive",
    description:
      "Your self-hosted Immich library as a native folder in the macOS Finder. Like iCloud Drive, but for your own server.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Findich: an Immich drive",
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
