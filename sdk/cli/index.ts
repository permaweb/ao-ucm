#!/usr/bin/env node
// import fs from 'fs';
// import path from 'path';
import minimist from 'minimist';

import { CLI_ARGS } from './helpers/config.ts';
import { ArgumentsInterface, CommandInterface, OptionInterface } from './helpers/types.ts';
import { checkProcessEnv, log } from './helpers/utils.ts';

// import { fileURLToPath } from 'node:url';
// import { dirname } from 'node:path';

// const __dirname_local =
//   typeof __dirname !== 'undefined'
//     ? __dirname
//     : dirname(fileURLToPath(import.meta.url));

import helpCommand from './commands/help.ts';
import reportCommand from './commands/report.ts';

(async function () {
	const commands = new Map<string, any>();

	commands.set('help', helpCommand);
	commands.set('report', reportCommand);

	try {
		const argv = minimist(process.argv.slice(2));
		const command = argv._[0];
		const commandValues = argv._.slice(1);

		if (commands.has(command)) {
			await commands.get(command).execute({ argv, commandValues, commands });
		} else {
			if (command) log(`Command not found: ${command}`, 1);
			await commands.get(CLI_ARGS.commands.help).execute({ argv, commandValues, commands });
		}
	} catch (error) {
		console.error('Error initializing CLI:', error);
	}
})();