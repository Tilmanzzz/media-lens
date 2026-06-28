import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  env: {
    BACKEND_URL: process.env.BACKEND_URL ?? "http://localhost:8080",
  },
  // Fixes the HMR websocket block in development mode
  allowedDevOrigins: ['141.62.115.192', 'localhost'],
  images: {
    // Required to bypass SSRF blocks when Next.js fetches from internal Docker IPs
    dangerouslyAllowLocalIP: true,
    remotePatterns: [
      {
        protocol: "http",
        hostname: "localhost",
        port: "9000",
        pathname: "/**",
      },
      {
        protocol: "http",
        hostname: "minio",
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
  // Proxies audio requests from the client browser to the internal MinIO container
  async rewrites() {
    return [
      {
        source: "/storage/:path*",
        destination: "http://minio:9000/:path*",
      },
    ];
  },
};

export default nextConfig;
