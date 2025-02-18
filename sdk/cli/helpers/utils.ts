import clc from 'cli-color';
import { Spinner } from 'cli-spinner';

export class CliSpinner {
	private spinner: Spinner;
	private message: string;
	private spinnerString: string;

	constructor(
		message: string,
		spinnerString = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
	) {
		this.message = message;
		this.spinnerString = spinnerString;
		this.spinner = new Spinner(this.getMessage());
		this.spinner.setSpinnerString(this.spinnerString);
		this.spinner.start();
	}

	getMessage() {
		return `%s ${clc.green(this.message)}`
	}

	setMessage(message: string) {
		this.spinner.stop();
		this.message = message;
		this.spinner = new Spinner(this.getMessage());
		this.spinner.setSpinnerString(this.spinnerString);
		this.spinner.start();
	}

	start() {
		this.spinner.start();
	}
	
	stop(clear: boolean = true) {
		this.spinner.stop(clear);
	}
}

export function log(message: any, status?: 0 | 1): void {
	const now = new Date();
	const formattedDate = now.toISOString().slice(0, 19).replace('T', ' ');
	if (status !== undefined) {
		console.log(`${formattedDate} - ${status === 0 ? clc.green(message) : clc.red(message)}`);
	} else {
		console.log(`${formattedDate} - ${message}`);
	}
}

export function checkProcessEnv(processArg: string): string {
	return processArg.indexOf('ts-node') || processArg.indexOf('--loader ts-node/esm') > -1 ? '.ts' : '.js';
}

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

export function formatCount(count: string): string {
	if (count === '0' || !Number(count)) return '0';

	if (count.includes('.')) {
		let parts = count.split('.');
		parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',');

		// Find the position of the last non-zero digit within the first 6 decimal places
		let index = 0;
		for (let i = 0; i < Math.min(parts[1].length, 6); i++) {
			if (parts[1][i] !== '0') {
				index = i + 1;
			}
		}

		if (index === 0) {
			// If all decimals are zeros, keep two decimal places
			parts[1] = '00';
		} else {
			// Otherwise, truncate to the last non-zero digit
			parts[1] = parts[1].substring(0, index);

			// If the decimal part is longer than 4 digits, truncate to 4 digits
			if (parts[1].length > 4 && parts[1].substring(0, 4) !== '0000') {
				parts[1] = parts[1].substring(0, 4);
			}
		}

		return parts.join('.');
	} else {
		return count.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
	}
}