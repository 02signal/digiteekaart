import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

export default defineConfig({
  site: "https://digiteekaart.ee",
  integrations: [sitemap()],
  output: "static"
});
