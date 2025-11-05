import { randomBytes } from 'crypto';

export function createPathSegment(): string {
  return randomBytes(4).toString('hex');
}

export function joinPath(parentPath: string | null, segment: string): string {
  return parentPath ? `${parentPath}.${segment}` : segment;
}

export function sortByPath<T extends { path: string }>(items: T[]): T[] {
  return [...items].sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
}
