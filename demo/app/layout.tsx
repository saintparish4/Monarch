import type { Metadata, Viewport } from "next";
import { Inter, Inter_Tight, JetBrains_Mono } from "next/font/google";
import type { ReactNode } from "react";

import "./globals.css";

// Three faces, each with one job: a tight grotesque for headings, Inter for
// everything read as a sentence, and a monospace for addresses, hashes and the
// small labels above sections. `next/font` downloads them at build time and
// serves them from this origin, so a visitor's browser never calls a font host.
const display = Inter_Tight({ subsets: ["latin"], weight: ["500", "600"], variable: "--font-display" });
const body = Inter({ subsets: ["latin"], weight: ["400", "500", "600"], variable: "--font-body" });
const mono = JetBrains_Mono({ subsets: ["latin"], weight: ["400", "500"], variable: "--font-mono" });

export const metadata: Metadata = {
  title: "Monarch — a sponsored transaction from a wallet with zero ETH",
  description: "An ERC-4337 paymaster on Base Sepolia that lets an app pay its users' gas.",
};

export const viewport: Viewport = {
  themeColor: "#bff660",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className={`${display.variable} ${body.variable} ${mono.variable}`}>
      <body>{children}</body>
    </html>
  );
}
