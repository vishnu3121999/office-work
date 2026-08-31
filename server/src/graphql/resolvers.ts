import prisma from '../db';
import { buildMessageTree } from '../services/messageTree';
import { createMessage as createMessageRecord } from '../services/messageService';
import chatController from '../controllers/chatController';

export const resolvers = {
  Query: {
    conversation: async (_: unknown, args: { id: string }) => {
      const conversation = await prisma.conversation.findUnique({
        where: { id: args.id }
      });

      if (!conversation) {
        return null;
      }

      return conversation;
    },
    message: (_: unknown, args: { id: string }) =>
      prisma.message.findUnique({ where: { id: args.id } }),
    messageChildren: async (_: unknown, args: { messageId: string }) =>
      prisma.message.findMany({
        where: { parentId: args.messageId },
        orderBy: { path: 'asc' }
      }),
    promptForMessage: (_: unknown, args: { messageId: string }) =>
      chatController.assemblePromptForMessage(args.messageId)
  },
  Mutation: {
    createConversation: async (
      _: unknown,
      args: {
        input: {
          title: string;
          description?: string | null;
          rootMessage?: {
            role: string;
            content: string;
          } | null;
        };
      }
    ) => {
      const conversation = await prisma.conversation.create({
        data: {
          title: args.input.title,
          description: args.input.description ?? null
        }
      });

      if (args.input.rootMessage) {
        await createMessageRecord({
          conversationId: conversation.id,
          role: args.input.rootMessage.role,
          content: args.input.rootMessage.content
        });
      }

      return conversation;
    },
    createMessage: async (
      _: unknown,
      args: {
        input: {
          conversationId: string;
          role: string;
          content: string;
          parentId?: string | null;
        };
      }
    ) =>
      createMessageRecord({
        conversationId: args.input.conversationId,
        role: args.input.role,
        content: args.input.content,
        parentId: args.input.parentId ?? undefined
      }),
    branchMessage: async (
      _: unknown,
      args: {
        messageId: string;
        input: {
          role: string;
          content: string;
        };
      }
    ) => {
      const parent = await prisma.message.findUnique({
        where: { id: args.messageId }
      });

      if (!parent) {
        throw new Error('Parent message not found');
      }

      return createMessageRecord({
        conversationId: parent.conversationId,
        role: args.input.role,
        content: args.input.content,
        parentId: parent.id
      });
    }
  },
  Conversation: {
    messages: async (conversation: { id: string }) => {
      const messages = await prisma.message.findMany({
        where: { conversationId: conversation.id }
      });
      return buildMessageTree(messages);
    }
  },
  Message: {
    children: (message: { id: string; children?: unknown }) => {
      if (Array.isArray((message as { children?: unknown }).children)) {
        return (message as { children: unknown[] }).children;
      }

      return prisma.message.findMany({
        where: { parentId: message.id },
        orderBy: { path: 'asc' }
      });
    }
  }
};
