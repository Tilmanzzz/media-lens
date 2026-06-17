import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  env: {
    BACKEND_URL: process.env.BACKEND_URL ?? "http://localhost:8080",
  },
  images: {
    remotePatterns: [
      {
        protocol: "http",
        hostname: "localhost",
        port: "9000",
        pathname: "/**",
      },
      {
        protocol: "https",
        hostname: "**",
        pathname: "/**",
      },
    ],
  },
};

export default nextConfig;
