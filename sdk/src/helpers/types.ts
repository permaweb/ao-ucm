export type DependenciesType = {
	ao: any;
	signer?: any;
	arweave?: any;
}

export type OrderbookCreateType = {
	assetId: string;
	collectionId?: string;
}

export type ArNSDetailsType = {
	name: string;
	type: 'lease' | 'permabuy';
	years?: number;
	undernameLimit?: number;
}

export type OrderCreateType = {
	orderbookId: string;
	creatorId: string;
	dominantToken: string;
	swapToken: string;
	quantity: string;
	action: 'Transfer' | 'Run-Action' | 'ArNS-Transfer';
	unitPrice?: string;
	denomination?: string;
	arns?: ArNSDetailsType;
}

export type OrderCancelType = {
	orderbookId: string;
	orderId: string;
	creatorId: string;
	dominantToken: string;
	swapToken: string;
}