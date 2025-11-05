import prisma from '../db';
import { sortByPath } from '../utils/path';

export interface PromptMessage {
  id: string;
  role: string;
  content: string;
}

export class ChatController {
  async assemblePromptForMessage(messageId: string): Promise<PromptMessage[]> {
    const message = await prisma.message.findUnique({
      where: { id: messageId }
    });

    if (!message) {
      throw new Error(`Message ${messageId} not found`);
    }

    const segments = message.path.split('.');
    const ancestorPaths: string[] = [];

    for (let i = 0; i < segments.length; i++) {
      ancestorPaths.push(segments.slice(0, i + 1).join('.'));
    }

    const branchMessages = await prisma.message.findMany({
      where: {
        conversationId: message.conversationId,
        path: { in: ancestorPaths }
      }
    });

    const ordered = sortByPath(branchMessages);

    return ordered.map((node) => ({
      id: node.id,
      role: node.role,
      content: node.content
    }));
  }
}

const chatController = new ChatController();
export default chatController;
