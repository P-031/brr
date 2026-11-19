import "dotenv/config";
import { createApp } from "./app";
import { env } from "./env";
import { startWorker } from "./jobs";

startWorker();
const app = createApp();
const server = app.listen(env.port, "0.0.0.0", () => {
  console.log(`API ready at http://0.0.0.0:${env.port}`);
});

server.on("error", (error) => {
  console.error(error);
  process.exit(1);
});
