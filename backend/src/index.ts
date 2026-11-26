import "dotenv/config";
import { createApp } from "./app";
import { env } from "./env";
import { prisma } from "./prisma";

const app = createApp();
const server = app.listen(env.port, "0.0.0.0", () => {
  console.log(`API ready at http://0.0.0.0:${env.port}`);
});

server.on("error", (error) => {
  console.error(error);
  process.exit(1);
});

function shutdown() {
  server.close(() => {
    void prisma.$disconnect().finally(() => process.exit(0));
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
