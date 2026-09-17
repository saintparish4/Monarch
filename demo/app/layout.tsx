import type { Metadata } from "next";
import type { ReactNode } from "react";

import "./globals.css";

export const metadata: Metadata = {
  title: "Monarch — a sponsored transaction from a wallet with zero ETH",
  description: "An ERC-4337 paymaster on Base Sepolia that lets an app pay its users' gas.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
