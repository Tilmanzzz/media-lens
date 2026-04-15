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
      className={`${courierPrime} ${dmSans} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">
        <Sidebar></Sidebar>
        <main>{children}</main>
      </body>
    </html>
  );
}
