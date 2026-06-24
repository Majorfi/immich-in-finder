import { ImageResponse } from "next/og";
import { readFileSync } from "fs";
import { join } from "path";

export const runtime = "nodejs";
export const alt = "Findich: an Immich drive for the macOS Finder";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const logo = `data:image/png;base64,${readFileSync(
  join(process.cwd(), "public", "logo-og.png"),
).toString("base64")}`;

export default function Image() {
  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        padding: "96px",
        background:
          "linear-gradient(135deg, #ffffff 0%, #fafafa 55%, #eef5ff 100%)",
        fontFamily: "sans-serif",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: "28px" }}>
        <img width="116" height="116" src={logo} alt="" />
        <div
          style={{
            fontSize: "92px",
            fontWeight: 800,
            color: "#0a0a0a",
            letterSpacing: "-3px",
          }}
        >
          Findich
        </div>
      </div>

      <div
        style={{
          marginTop: "44px",
          fontSize: "52px",
          fontWeight: 700,
          color: "#0a0a0a",
          letterSpacing: "-1.5px",
          maxWidth: "900px",
          lineHeight: 1.15,
        }}
      >
        An Immich drive for your macOS Finder.
      </div>

      <div style={{ marginTop: "28px", fontSize: "30px", color: "#525252" }}>
        Albums, timeline, people &amp; places as real folders · on-demand · pay
        what you want
      </div>
    </div>,
    size,
  );
}
