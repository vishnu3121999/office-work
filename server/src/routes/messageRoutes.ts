import { Router } from 'express';
import { z } from 'zod';
import prisma from '../db';
import { createMessage, getMessageChildren } from '../services/messageService';
import chatController from '../controllers/chatController';

const router = Router();

const createMessageSchema = z.object({
  conversationId: z.string(),
  role: z.string(),
  content: z.string(),
  parentId: z.string().optional()
});

const createChildSchema = z.object({
  role: z.string(),
  content: z.string()
});

router.get('/:id', async (req, res, next) => {
  try {
    const message = await prisma.message.findUnique({
      where: { id: req.params.id }
    });

    if (!message) {
      res.status(404).json({ message: 'Message not found' });
      return;
    }

    res.json(message);
  } catch (error) {
    next(error);
  }
});

router.post('/', async (req, res, next) => {
  try {
    const payload = createMessageSchema.parse(req.body);
    const message = await createMessage(payload);
    res.status(201).json(message);
  } catch (error) {
    if (error instanceof Error) {
      if (/Parent message/.test(error.message) || /Conversation/.test(error.message)) {
        res.status(404).json({ message: error.message });
        return;
      }

      if (/different conversation/.test(error.message)) {
        res.status(400).json({ message: error.message });
        return;
      }
    }
    next(error);
  }
});

router.get('/:id/children', async (req, res, next) => {
  try {
    const message = await prisma.message.findUnique({
      where: { id: req.params.id }
    });

    if (!message) {
      res.status(404).json({ message: 'Message not found' });
      return;
    }

    const children = await getMessageChildren(message.id);
    res.json({
      parent: message,
      children
    });
  } catch (error) {
    next(error);
  }
});

router.post('/:id/children', async (req, res, next) => {
  try {
    const message = await prisma.message.findUnique({
      where: { id: req.params.id }
    });

    if (!message) {
      res.status(404).json({ message: 'Message not found' });
      return;
    }

    const payload = createChildSchema.parse(req.body);

    const child = await createMessage({
      conversationId: message.conversationId,
      role: payload.role,
      content: payload.content,
      parentId: message.id
    });

    res.status(201).json(child);
  } catch (error) {
    if (error instanceof Error) {
      if (/Parent message/.test(error.message) || /Conversation/.test(error.message)) {
        res.status(404).json({ message: error.message });
        return;
      }

      if (/different conversation/.test(error.message)) {
        res.status(400).json({ message: error.message });
        return;
      }
    }
    next(error);
  }
});

router.get('/:id/prompt', async (req, res, next) => {
  try {
    const prompt = await chatController.assemblePromptForMessage(req.params.id);
    res.json({ prompt });
  } catch (error) {
    if (error instanceof Error && /not found/i.test(error.message)) {
      res.status(404).json({ message: error.message });
      return;
    }
    next(error);
  }
});

export default router;
