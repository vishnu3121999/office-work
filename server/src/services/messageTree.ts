import { Message } from '@prisma/client';

export interface MessageNode extends Message {
  children: MessageNode[];
}

export function buildMessageTree(messages: Message[]): MessageNode[] {
  const nodes = new Map<string, MessageNode>();
  const roots: MessageNode[] = [];

  messages.forEach((message) => {
    nodes.set(message.id, { ...message, children: [] });
  });

  nodes.forEach((node) => {
    if (node.parentId) {
      const parent = nodes.get(node.parentId);
      if (parent) {
        parent.children.push(node);
        return;
      }
    }
    roots.push(node);
  });

  const sortChildren = (items: MessageNode[]) => {
    items.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
    items.forEach((item) => sortChildren(item.children));
  };

  sortChildren(roots);
  return roots;
}
