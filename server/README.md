# Branching Chat Server

This server exposes REST and GraphQL APIs for managing branching conversations. Messages reference their parent so that a tree of conversation turns can be explored, branched, and replayed when assembling prompts for an AI model.

## Getting started

```bash
cd server
cp .env.example .env
# Adjust DATABASE_URL if needed (defaults to a local SQLite file)
npm install
npm run prisma:generate
npm run prisma:migrate
npm run prisma:seed
npm run build
npm start
```

During development you can run `npm run dev` to start the TypeScript server with hot reloading.

## REST endpoints

- `GET /conversations/:id` – fetch a conversation with the complete message tree.
- `POST /conversations` – create a conversation and optionally add a root message.
- `POST /messages` – create a message, optionally referencing a parent to attach to an existing branch.
- `GET /messages/:id` – fetch a single message.
- `GET /messages/:id/children` – list the direct children of a message.
- `POST /messages/:id/children` – create a branched reply under a message.
- `GET /messages/:id/prompt` – return the ordered prompt (root ➝ node) for the specified message.

## GraphQL schema

GraphQL is available at `/graphql`. Core operations include:

- `conversation(id: ID!)` – fetch a conversation with nested messages.
- `message(id: ID!)` and `messageChildren(messageId: ID!)` – inspect specific nodes.
- `promptForMessage(messageId: ID!)` – return the prompt path for a message.
- `createConversation`, `createMessage`, and `branchMessage` – mutations for authoring content.

## Seed data

The seed script installs an example conversation that illustrates branching:

- System prompt
- Initial user request
- Two assistant replies branching from the user request
- A follow-up user reply attached to one branch

This data is useful for exercising both the REST and GraphQL APIs immediately after setup.
