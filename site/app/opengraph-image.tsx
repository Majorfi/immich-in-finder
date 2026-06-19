import { ImageResponse } from "next/og";

export const alt = "Findich — an Immich drive for the macOS Finder";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

// Branded social card, rendered at build time. Mirrors the site's light, clean
// Apple-ish look so link previews match the landing page.
export default function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "96px",
          background:
            "linear-gradient(135deg, #ffffff 0%, #f5f7fb 55%, #eaf2ff 100%)",
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: "28px" }}>
          <div
            style={{
              width: "108px",
              height: "108px",
              borderRadius: "26px",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              background: "linear-gradient(180deg, #54a8ff 0%, #0071e3 100%)",
              boxShadow: "0 12px 40px rgba(0,113,227,0.35)",
            }}
          >
            <svg width="60" height="48" viewBox="0 0 64 52" fill="white">
              <path d="M2 8c0-2.8 2.2-5 5-5h15l5 6h30c2.8 0 5 2.2 5 5v31c0 2.8-2.2 5-5 5H7c-2.8 0-5-2.2-5-5V8z" />
            </svg>
          </div>
          <div style={{ fontSize: "92px", fontWeight: 800, color: "#1d1d1f", letterSpacing: "-3px" }}>
            Findich
          </div>
        </div>

        <div
          style={{
            marginTop: "44px",
            fontSize: "52px",
            fontWeight: 700,
            color: "#1d1d1f",
            letterSpacing: "-1.5px",
            maxWidth: "900px",
            lineHeight: 1.15,
          }}
        >
          An Immich drive for your macOS Finder.
        </div>

        <div style={{ marginTop: "28px", fontSize: "30px", color: "#6e6e73" }}>
          Albums, timeline, people &amp; places as real folders · on-demand · free &amp; open source
        </div>
      </div>
    ),
    size
  );
}
