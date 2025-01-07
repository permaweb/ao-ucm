export function getTagValue(list: { [key: string]: any }[], name: string): string | null {
	for (let i = 0; i < list.length; i++) {
		if (list[i]) {
			if (list[i]!.name === name) {
				return list[i]!.value as string;
			}
		}
	}
	return null;
}

export function getTagValueForAction(messages: any[], tagName: string, action: string, defaultValue: string): string {
	for (const message of messages) {
		const actionTag = message.Tags.find((tag: any) => tag.name === 'Action' && tag.value === action);
		if (actionTag) {
			const messageTag = message.Tags.find((tag: any) => tag.name === tagName);
			if (messageTag) return messageTag.value;
		}
	}
	return defaultValue;
}

export const globalLog = (...args: any[]) => {
    console.log('[@permaweb/ucm]', ...args);
};