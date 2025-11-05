import prisma from '../db';
import { createPathSegment, joinPath } from '../utils/path';

interface MessageInput {
  conversationId: string;
  role: string;
  content: string;
  parentId?: string | null;
}

export async function createMessage({ conversationId, role, content, parentId }: MessageInput) {
  let path: string;

  if (parentId) {
    const parent = await prisma.message.findUnique({
      where: { id: parentId }
    });

    if (!parent) {
      throw new Error(`Parent message ${parentId} not found`);
    }

    if (parent.conversationId !== conversationId) {
      throw new Error('Parent message belongs to a different conversation');
    }

    const segment = createPathSegment();
    path = joinPath(parent.path, segment);
  } else {
    const conversation = await prisma.conversation.findUnique({
      where: { id: conversationId }
    });

    if (!conversation) {
      throw new Error(`Conversation ${conversationId} not found`);
    }

    const segment = createPathSegment();
    path = segment;
  }

  const message = await prisma.message.create({
    data: {
      conversationId,
      parentId: parentId ?? null,
      role,
      content,
      path
    }
  });

  await prisma.conversation.update({
    where: { id: conversationId },
    data: { updatedAt: new Date() }
  });

  return message;
}

export async function getMessageChildren(messageId: string) {
  const children = await prisma.message.findMany({
    where: { parentId: messageId },
    orderBy: { path: 'asc' }
  });
  return children;
}
