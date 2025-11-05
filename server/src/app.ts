import express, { Application, NextFunction, Request, Response } from 'express';
import { ApolloServer } from 'apollo-server-express';
import conversationRoutes from './routes/conversationRoutes';
import messageRoutes from './routes/messageRoutes';
import { typeDefs } from './graphql/schema';
import { resolvers } from './graphql/resolvers';
import dotenv from 'dotenv';
import { ZodError } from 'zod';

dotenv.config();

export async function createApp(): Promise<Application> {
  const app = express();

  app.use(express.json());

  app.use('/conversations', conversationRoutes);
  app.use('/messages', messageRoutes);

  const apolloServer = new ApolloServer({ typeDefs, resolvers });
  await apolloServer.start();
  apolloServer.applyMiddleware({ app, path: '/graphql' });

  app.use(
    (error: unknown, _req: Request, res: Response, _next: NextFunction) => {
      if (error instanceof ZodError) {
        res.status(400).json({ message: 'Validation error', issues: error.issues });
        return;
      }

      if (error instanceof Error) {
        res.status(500).json({ message: error.message });
        return;
      }

      res.status(500).json({ message: 'Unexpected error' });
    }
  );

  return app;
}
