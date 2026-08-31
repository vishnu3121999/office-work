import { createServer } from 'http';
import { createApp } from './app';

const PORT = parseInt(process.env.PORT || '4000', 10);

async function bootstrap() {
  const app = await createApp();
  const httpServer = createServer(app);

  httpServer.listen(PORT, () => {
    console.log(`Server listening on port ${PORT}`);
  });
}

bootstrap().catch((error) => {
  console.error('Failed to start server', error);
  process.exit(1);
});
