// A macOS Finder window (light appearance) rebuilt in pure CSS/SVG — no
// screenshots, so it stays crisp at every size and ships zero image bytes.

const SIDEBAR = {
  Favorites: [
    "AirDrop",
    "Recents",
    "Applications",
    "Desktop",
    "Downloads",
    "Documents",
    "Pictures",
  ],
  Locations: ["Macintosh HD", "Findich"],
};

const FOLDERS = ["Albums", "Timeline", "People", "Places", "Tags", "Favorites"];

// Gradient stand-ins for photo thumbnails (hue pairs picked to read as photos).
const PHOTOS: Array<{ from: string; to: string; cloud?: boolean }> = [
  { from: "#FF9F0A", to: "#FF375F" },
  { from: "#30D158", to: "#0A84FF", cloud: true },
  { from: "#BF5AF2", to: "#0A84FF" },
  { from: "#FFD60A", to: "#FF9F0A" },
  { from: "#64D2FF", to: "#5E5CE6", cloud: true },
  { from: "#FF6482", to: "#BF5AF2" },
  { from: "#0A84FF", to: "#30D158" },
  { from: "#FF375F", to: "#FF9F0A", cloud: true },
  { from: "#5E5CE6", to: "#BF5AF2" },
  { from: "#FFD60A", to: "#30D158" },
  { from: "#64D2FF", to: "#0A84FF" },
  { from: "#BF5AF2", to: "#FF6482", cloud: true },
];

function FolderIcon() {
  return (
    <svg viewBox="0 0 64 52" className="h-9 w-12 sm:h-11 sm:w-14" aria-hidden>
      <defs>
        <linearGradient id="fold" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#6FB6FF" />
          <stop offset="1" stopColor="#1e83f7" />
        </linearGradient>
      </defs>
      <path
        d="M2 8c0-2.8 2.2-5 5-5h15l5 6h30c2.8 0 5 2.2 5 5v31c0 2.8-2.2 5-5 5H7c-2.8 0-5-2.2-5-5V8z"
        fill="url(#fold)"
      />
      <path
        d="M2 14h60v25c0 2.8-2.2 5-5 5H7c-2.8 0-5-2.2-5-5V14z"
        fill="#3FA0FF"
        opacity="0.9"
      />
    </svg>
  );
}

function CloudBadge() {
  return (
    <span className="absolute right-1 bottom-1 grid h-4 w-4 place-items-center rounded-full bg-black/45 backdrop-blur">
      <svg viewBox="0 0 16 16" className="h-2.5 w-2.5" fill="white" aria-hidden>
        <path d="M4.5 12a3 3 0 0 1-.4-5.98 4 4 0 0 1 7.8.98H12a2.5 2.5 0 0 1 0 5H4.5z" />
        <path
          d="M8 6.5v3.6M6.6 8.7L8 10.1l1.4-1.4"
          stroke="white"
          strokeWidth="1.1"
          fill="none"
          strokeLinecap="round"
        />
      </svg>
    </span>
  );
}

export default function FinderWindow() {
  return (
    <div className="hairline overflow-hidden rounded-xl bg-white text-left">
      {/* Title bar */}
      <div className="flex items-center gap-2 border-b border-black/8 bg-[#f6f6f6] px-4 py-2.5">
        <span className="flex gap-1.5">
          <i className="h-3 w-3 rounded-full bg-[#FF5F57]" />
          <i className="h-3 w-3 rounded-full bg-[#FEBC2E]" />
          <i className="h-3 w-3 rounded-full bg-[#28C840]" />
        </span>
        <span className="ml-2 hidden items-center gap-1.5 text-[13px] font-semibold text-[#3a3a3c] sm:flex">
          <img src="/logo.svg" alt="" className="h-4 w-4" />
          Findich
        </span>
        <span className="ml-auto hidden h-6 w-40 items-center gap-1.5 rounded-md bg-black/5 px-2 text-[11px] text-black/35 md:flex">
          <svg
            viewBox="0 0 16 16"
            className="h-3 w-3"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.5"
            aria-hidden
          >
            <circle cx="7" cy="7" r="4.5" />
            <path d="m10.5 10.5 3 3" strokeLinecap="round" />
          </svg>
          Search
        </span>
      </div>

      <div className="flex">
        {/* Sidebar */}
        <aside className="hidden w-44 shrink-0 border-r border-black/8 bg-[#fbfbfd] px-3 py-3 sm:block">
          {Object.entries(SIDEBAR).map(([section, items]) => (
            <div key={section} className="mb-3">
              <p className="px-2 pb-1 text-[10px] font-semibold tracking-wide text-black/35">
                {section}
              </p>
              {items.map((item) => {
                const active = item === "Findich";
                return (
                  <p
                    key={item}
                    className={`flex items-center gap-2 rounded-md px-2 py-[3px] text-[12px] ${
                      active
                        ? "bg-accent font-medium text-white"
                        : "text-[#333]"
                    }`}
                  >
                    {item === "Findich" ? (
                      <span className="grid h-4 w-4 place-items-center rounded-[4px] bg-white">
                        <img src="/logo.svg" alt="" className="h-3.5 w-3.5" />
                      </span>
                    ) : (
                      <svg
                        viewBox="0 0 16 16"
                        className="h-3.5 w-3.5 text-[#1e83f7]"
                        fill="currentColor"
                        aria-hidden
                      >
                        {item === "Macintosh HD" ? (
                          <path
                            fillRule="evenodd"
                            clipRule="evenodd"
                            d="M2.5 4.5h11A1.5 1.5 0 0 1 15 6v4a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 1 10V6a1.5 1.5 0 0 1 1.5-1.5zM11 8a1 1 0 1 0 2 0 1 1 0 0 0-2 0z"
                          />
                        ) : (
                          <path d="M1 4c0-.6.4-1 1-1h4l1.2 1.5H14c.6 0 1 .4 1 1V12c0 .6-.4 1-1 1H2c-.6 0-1-.4-1-1V4z" />
                        )}
                      </svg>
                    )}
                    {item}
                  </p>
                );
              })}
            </div>
          ))}
        </aside>

        {/* Content */}
        <div className="min-w-0 flex-1 bg-white p-5 sm:p-6">
          <div className="grid grid-cols-3 gap-x-2 gap-y-4 sm:grid-cols-6">
            {FOLDERS.map((name) => (
              <figure key={name} className="flex flex-col items-center gap-1">
                <FolderIcon />
                <figcaption className="text-[11px] text-[#333]">
                  {name}
                </figcaption>
              </figure>
            ))}
          </div>

          <p className="mt-6 mb-2.5 text-[11px] font-medium text-black/35">
            Albums › Sitges — 239 items
          </p>
          <div className="grid grid-cols-6 gap-2.5">
            {PHOTOS.map((photo, index) => (
              <div
                key={index}
                className="relative aspect-square rounded-md"
                style={{
                  background: `linear-gradient(135deg, ${photo.from}, ${photo.to})`,
                }}
              >
                {photo.cloud && <CloudBadge />}
              </div>
            ))}
          </div>

          <p className="mt-5 border-t border-black/8 pt-3 text-center text-[10px] text-black/30">
            8,836 items · originals download on demand
          </p>
        </div>
      </div>
    </div>
  );
}
