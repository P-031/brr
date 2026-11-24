import "dotenv/config";
import { createApp } from "./app";
import { env } from "./env";

const app = createApp();
const server = app.listen(env.port, "127.0.0.1", () => {
  console.log(`API ready at http://127.0.0.1:${env.port}`);
});

server.on("error", (error) => {
  console.error(error);
  process.exit(1);
});
