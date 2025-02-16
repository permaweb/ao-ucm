import minimist from 'minimist';

export interface ArgumentsInterface {
	argv: minimist.ParsedArgs;
	commandValues: string[];
	options: Map<string, OptionInterface>;
	commands: Map<string, CommandInterface>;
}

export interface OptionInterface {
	name: string;
	description: string;
	arg: string;
	suboptions?: OptionInterface[];
	topLevel?: boolean;
}

export interface CommandInterface {
	name: string;
	options?: any[];
	args?: string[];
	description: string;
	execute: (args: any) => Promise<void>;
}
