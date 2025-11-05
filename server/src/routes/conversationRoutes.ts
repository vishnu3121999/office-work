import { Router } from 'express';
import { z } from 'zod';
import prisma from '../db';
import { buildMessageTree } from '../services/messageTree';
import { createMessage } from '../services/messageService';

const router = Router();

const createConversationSchema = z.object({
  title: z.string(),
  description: z.string().optional(),
  rootMessage: z
    .object({
      role: z.string(),
      content: z.string()
    })
    .optional()
});

router.post('/', async (req, res, next) => {
  try {
    const payload = createConversationSchema.parse(req.body);
    const conversation = await prisma.conversation.create({
      data: {
        title: payload.title,
        description: payload.description
      }
    });

    let rootMessage = null;

    if (payload.rootMessage) {
      rootMessage = await createMessage({
        conversationId: conversation.id,
        role: payload.rootMessage.role,
        content: payload.rootMessage.content
      });
    }

    res.status(201).json({
      conversation,
      rootMessage
    });
  } catch (error) {
    next(error);
  }
});

router.get('/:id', async (req, res, next) => {
  try {
    const conversation = await prisma.conversation.findUnique({
      where: { id: req.params.id }
    });

    if (!conversation) {
      res.status(404).json({ message: 'Conversation not found' });
      return;
    }

    const messages = await prisma.message.findMany({
      where: { conversationId: conversation.id }
    });

    const tree = buildMessageTree(messages);

    res.json({
      conversation,
      messages: tree
    });
  } catch (error) {
    next(error);
  }
});

export default router;
