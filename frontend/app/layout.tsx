import "./globals.css";

export const metadata = {
  title: "Canada Tourist Chatbot",
  description: "Tourist attractions assistant for Canada"
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-black text-zinc-100">{children}</body>
    </html>
  );
}

