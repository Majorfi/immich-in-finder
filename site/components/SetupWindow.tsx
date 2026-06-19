// A macOS setup window (light) for Findich, rebuilt in pure CSS/SVG — mirrors
// the real SwiftUI app so the page shows the actual UI and ships zero image bytes.

import type { ReactNode } from "react";

const SECTIONS: { name: string; tint: string; icon: ReactNode }[] = [
  {
    name: "Albums",
    tint: "#1e83f7",
    icon: (
      <>
        <rect x="3" y="4" width="10" height="8" rx="1.6" />
        <circle cx="5.8" cy="6.6" r="1" fill="currentColor" />
        <path d="M3 10.5 6 8l2 1.8L10 7l3 3.5z" fill="currentColor" />
      </>
    ),
  },
  {
    name: "Timeline",
    tint: "#f5871f",
    icon: (
      <>
        <rect x="2.6" y="3.4" width="10.8" height="9.4" rx="1.7" />
        <path d="M2.6 6h10.8" stroke="white" strokeWidth="1.1" />
        <path
          d="M5 2.4v2M11 2.4v2"
          stroke="white"
          strokeWidth="1.1"
          strokeLinecap="round"
        />
      </>
    ),
  },
  {
    name: "People",
    tint: "#34c759",
    icon: (
      <>
        <circle cx="6" cy="6" r="2.1" />
        <circle cx="10.6" cy="6.6" r="1.7" />
        <path d="M2.3 12.4c0-2 1.7-3.1 3.7-3.1s3.7 1.1 3.7 3.1z" />
        <path d="M9.4 9.5c1.7.1 3.3 1 3.3 2.9h-2.4" />
      </>
    ),
  },
  {
    name: "Places",
    tint: "#ff2d55",
    icon: (
      <>
        <path d="M8 1.8c-2.4 0-4.2 1.8-4.2 4.1 0 3 4.2 8 4.2 8s4.2-5 4.2-8c0-2.3-1.8-4.1-4.2-4.1z" />
        <circle cx="8" cy="5.9" r="1.5" fill="currentColor" />
      </>
    ),
  },
  {
    name: "Tags",
    tint: "#af52de",
    icon: (
      <>
        <path d="M7.3 2.5H3.4A.9.9 0 0 0 2.5 3.4v3.9c0 .24.1.47.26.64l5.3 5.3a.9.9 0 0 0 1.27 0l3.9-3.9a.9.9 0 0 0 0-1.27l-5.3-5.3A.9.9 0 0 0 7.3 2.5z" />
        <circle cx="5.3" cy="5.3" r="1.1" fill="currentColor" />
      </>
    ),
  },
  {
    name: "Favorites",
    tint: "#ff3b30",
    icon: (
      <path d="M8 13.3S2.9 9.9 2.9 6.4A2.6 2.6 0 0 1 8 5.2a2.6 2.6 0 0 1 5.1 1.2C13.1 9.9 8 13.3 8 13.3z" />
    ),
  },
];

function Toggle() {
  return (
    <span className="relative inline-block h-[15px] w-[26px] shrink-0 rounded-full bg-[#1e83f7]">
      <span className="absolute right-[1.5px] top-[1.5px] h-3 w-3 rounded-full bg-white shadow-[0_1px_2px_rgba(0,0,0,0.25)]" />
    </span>
  );
}

export default function SetupWindow() {
  return (
    <div className="hairline mx-auto w-full max-w-[420px] overflow-hidden rounded-xl bg-white text-left">
      {/* Title bar */}
      <div className="flex items-center gap-2 border-b border-black/8 bg-[#f6f6f6] px-4 py-2.5">
        <span className="flex gap-1.5">
          <i className="h-3 w-3 rounded-full bg-[#FF5F57]" />
          <i className="h-3 w-3 rounded-full bg-[#FEBC2E]" />
          <i className="h-3 w-3 rounded-full bg-[#28C840]" />
        </span>
        <span className="ml-1 text-[12px] font-medium text-black/45">
          Findich
        </span>
      </div>

      <div className="px-5 py-5">
        {/* Header */}
        <div className="flex items-center gap-3">
          <img src="/logo.svg" alt="" className="h-11 w-11" />
          <div className="min-w-0 flex-1">
            <p className="text-[15px] font-bold leading-tight">Findich</p>
            <p className="text-[12.5px] text-black/45">
              Your photo library, in Finder
            </p>
          </div>
          <span className="flex items-center gap-1.5 rounded-full bg-[#34c759]/12 px-2.5 py-1 text-[11px] font-semibold text-[#28a745]">
            <span className="h-1.5 w-1.5 rounded-full bg-[#28a745]" />
            Active
          </span>
        </div>

        {/* Server */}
        <p className="mt-5 mb-1.5 text-[12px] font-semibold text-black/55">
          Server
        </p>
        <div className="overflow-hidden rounded-[10px] bg-black/[0.035]">
          <div className="flex items-center gap-2.5 px-3 py-2.5">
            <svg
              viewBox="0 0 16 16"
              className="h-[15px] w-[15px] text-black/40"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.2"
              aria-hidden
            >
              <circle cx="8" cy="8" r="6" />
              <path d="M2 8h12M8 2c1.8 1.7 1.8 10.3 0 12M8 2c-1.8 1.7-1.8 10.3 0 12" />
            </svg>
            <span className="text-[13px] text-black/80">Address</span>
            <span className="ml-auto text-[13px] text-black/35">
              https://photos.example.com
            </span>
          </div>
          <div className="flex items-center gap-2.5 border-t border-black/5 px-3 py-2.5">
            <svg
              viewBox="0 0 16 16"
              className="h-[15px] w-[15px] text-black/40"
              fill="currentColor"
              aria-hidden
            >
              <path d="M10.5 2a3.5 3.5 0 0 0-3.4 4.3L2 11.4V14h2.6l.7-.7v-1.2h1.2l.7-.7v-1.2h1.2l.9-.9A3.5 3.5 0 1 0 10.5 2zm1 3a1 1 0 1 1 0-2 1 1 0 0 1 0 2z" />
            </svg>
            <span className="text-[13px] text-black/80">API Key</span>
            <span className="ml-auto text-[13px] text-black/35">
              Paste your API key
            </span>
            <svg
              viewBox="0 0 16 16"
              className="h-[15px] w-[15px] text-black/35"
              fill="currentColor"
              aria-hidden
            >
              <path d="M8 3.5C4.5 3.5 1.7 6 1 8c.7 2 3.5 4.5 7 4.5s6.3-2.5 7-4.5c-.7-2-3.5-4.5-7-4.5zm0 7.5a3 3 0 1 1 0-6 3 3 0 0 1 0 6z" />
              <circle cx="8" cy="8" r="1.4" />
            </svg>
          </div>
        </div>

        {/* Folders */}
        <p className="mt-4 mb-1.5 text-[12px] font-semibold text-black/55">
          Folders in Finder
        </p>
        <div className="overflow-hidden rounded-[10px] bg-black/[0.035]">
          {SECTIONS.map((section, index) => (
            <div
              key={section.name}
              className={`flex items-center gap-2.5 px-3 py-2 ${index > 0 ? "border-t border-black/5" : ""}`}
            >
              <span
                className="grid h-[22px] w-[22px] place-items-center rounded-[6px] text-white"
                style={{ background: section.tint }}
              >
                <svg
                  viewBox="0 0 16 16"
                  className="h-[13px] w-[13px]"
                  fill="white"
                  aria-hidden
                >
                  {section.icon}
                </svg>
              </span>
              <span className="text-[13px] text-black/80">{section.name}</span>
              <span className="ml-auto">
                <Toggle />
              </span>
            </div>
          ))}
        </div>
        <p className="mt-2.5 text-[11.5px] leading-snug text-black/40">
          Choose which of Immich&apos;s views appear under “Findich” in the
          Finder sidebar.
        </p>
      </div>

      {/* Footer bar */}
      <div className="flex items-center justify-between border-t border-black/8 bg-black/[0.02] px-5 py-3.5">
        <span className="rounded-md border border-black/10 bg-white px-3 py-1.5 text-[12.5px] font-medium text-black/70">
          Disable
        </span>
        <span className="rounded-md bg-[#1e83f7] px-4 py-1.5 text-[12.5px] font-medium text-white shadow-sm">
          Update
        </span>
      </div>
    </div>
  );
}
