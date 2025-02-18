import clc from 'cli-color';
import figlet from 'figlet';

import { CLI_ARGS } from '../helpers/config.ts';
import { ArgumentsInterface, CommandInterface, OptionInterface } from '../helpers/types.ts';

const command: CommandInterface = {
	name: CLI_ARGS.commands.help,
	description: `Display help text`,
	execute: async (args: ArgumentsInterface): Promise<void> => {
		console.log(`${clc.blackBright(figlet.textSync('UCM', { font: 'Slant', width: process.stdout.columns }))}`);
		console.log(`\nUniversal Content Marketplace CLI`);
		console.log(`\nUsage: ${clc.green('ucm')} ${clc.green('[command]')} ${clc.green('[arguments]')}\n`);

		let formattedArgs: string;
		
		console.log(`${clc.blackBright('Commands')}`);
		args.commands.forEach((command) => {
			if (command.args && command.args.length) {
				formattedArgs = '<';
				command.args.forEach((arg: string) => {
					formattedArgs += arg;
				});
				formattedArgs += '>';
			}
			console.log(`${clc.green(command.name)}${formattedArgs ? ` ${formattedArgs}` : ''} ${clc.blackBright(`(${command.description})`)}`);
			if (command.options && command.options.length) {
				const spacer = (count: number) => ' '.repeat(count);
				console.log(`${spacer(4)}${clc.blackBright('Arguments')}`);
				{
					command.options.forEach((option) => {
						console.log(
							`${spacer(4)}${clc.green(`--${option.name}`)}${option.arg ? ` ${option.arg}` : ''} ${clc.blackBright(
								`(${option.description})`
							)}`
						);

						if (option.suboptions && option.suboptions.length) {
							console.log(`${' '.repeat(6)}${clc.blackBright('Suboptions')}`);
							logOptions(option.suboptions);
						}
					});
				}
			}
		});
		console.log('');
	},
};

function logOptions(options: OptionInterface[], indent = 6) {
	const spacer = (count: number) => ' '.repeat(count);
	const indentIncrease = 4;

	options.forEach((option) => {
		let label = clc.green(`--${option.name}`);
		if (option.topLevel) label = clc.white(option.name);

		console.log(
			`${spacer(indent)}${label}${option.arg ? ` ${option.arg}` : ''}${
				option.description ? ` ${clc.blackBright(`(${option.description})`)}` : ''
			}`
		);

		if (option.suboptions && option.suboptions.length) {
			logOptions(option.suboptions, indent + indentIncrease);
		}
	});
}

export default command;
