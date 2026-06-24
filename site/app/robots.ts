import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/" },
    sitemap: "https://findich.app/sitemap.xml",
    host: "https://findich.app",
  };
}
