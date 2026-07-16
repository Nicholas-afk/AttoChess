import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "The 278-Byte Chess Challenge",
  description: "Can you survive eight moves against an engine descended from a playable 278-byte DOS chess program?",
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000"),
  openGraph: {
    title: "Can you beat 278 bytes?",
    description: "A playable chess program fits in 278 bytes. Your move.",
    images: [{ url: "/og.png", width: 1200, height: 630, alt: "The 278-Byte Chess Challenge" }],
  },
  twitter: { card: "summary_large_image", title: "Can you beat 278 bytes?", description: "A playable chess program fits in 278 bytes. Your move.", images: ["/og.png"] },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
