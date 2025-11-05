import 'dotenv/config';
import prisma from '../src/db';
import { createMessage } from '../src/services/messageService';

async function main() {
  await prisma.message.deleteMany();
  await prisma.conversation.deleteMany();

  const conversation = await prisma.conversation.create({
    data: {
      title: 'Sample Product Discussion',
      description: 'Seed data showing a branching dialog'
    }
  });

  const system = await createMessage({
    conversationId: conversation.id,
    role: 'system',
    content: 'You are a helpful assistant specializing in productivity workflows.'
  });

  const userQuestion = await createMessage({
    conversationId: conversation.id,
    role: 'user',
    content: 'How can I organize my tasks for the week?',
    parentId: system.id
  });

  await createMessage({
    conversationId: conversation.id,
    role: 'assistant',
    content: 'Start by categorizing tasks by urgency and importance using a Eisenhower matrix.',
    parentId: userQuestion.id
  });

  const altAssistant = await createMessage({
    conversationId: conversation.id,
    role: 'assistant',
    content: 'Consider planning your week with time blocking each morning.',
    parentId: userQuestion.id
  });

  await createMessage({
    conversationId: conversation.id,
    role: 'user',
    content: 'What should I do if emergencies disrupt my time blocks?',
    parentId: altAssistant.id
  });

  console.log('Seed data created', { conversationId: conversation.id });
}

main()
  .catch((error) => {
    console.error('Failed to seed database', error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
