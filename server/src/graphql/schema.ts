import { gql } from 'apollo-server-express';

export const typeDefs = gql`
  type Conversation {
    id: ID!
    title: String!
    description: String
    createdAt: String!
    updatedAt: String!
    messages: [Message!]!
  }

  type Message {
    id: ID!
    conversationId: ID!
    parentId: ID
    role: String!
    content: String!
    path: String!
    createdAt: String!
    children: [Message!]!
  }

  type PromptMessage {
    id: ID!
    role: String!
    content: String!
  }

  input ConversationInput {
    title: String!
    description: String
    rootMessage: RootMessageInput
  }

  input MessageInput {
    conversationId: ID!
    role: String!
    content: String!
    parentId: ID
  }

  input RootMessageInput {
    role: String!
    content: String!
  }

  input BranchInput {
    role: String!
    content: String!
  }

  type Query {
    conversation(id: ID!): Conversation
    message(id: ID!): Message
    messageChildren(messageId: ID!): [Message!]!
    promptForMessage(messageId: ID!): [PromptMessage!]!
  }

  type Mutation {
    createConversation(input: ConversationInput!): Conversation!
    createMessage(input: MessageInput!): Message!
    branchMessage(messageId: ID!, input: BranchInput!): Message!
  }
`;
