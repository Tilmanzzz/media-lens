import type { Metadata } from "next";
import { Courier_Prime , DM_Sans } from "next/font/google";
import "./globals.css";
import { Sidebar } from "@/components/layout/sidebar";

const courierPrime = Courier_Prime({
  weight: "400",
  subsets: ["latin"],
});

const dmSans = DM_Sans({
  weight: "400",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Media Lens",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className="h-full antialiased"
    >
      <body className={`${courierPrime.className} ${dmSans.className} min-h-screen bg-[var(--background)] text-[var(--foreground)]`}>
        <Sidebar />
        <main className="ml-[240px] min-h-screen p-6">
          {children}
        </main>
      </body>
    </html>
  );
}