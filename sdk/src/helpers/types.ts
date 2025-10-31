export type DependenciesType = {
	ao: any;
	signer?: any;
	arweave?: any;
}

export type OrderbookCreateType = {
	assetId: string;
	collectionId?: string;
	writeToAsset?: boolean;
}

export type OrderCreateType = {
	creatorId?: string;
	walletAddress?: string;
	orderbookId: string;
	dominantToken: string;
	swapToken: string;
	quantity: string;
	action: 'Transfer' | 'Run-Action';
	unitPrice?: string;
	denomination?: string;
}

export type OrderCancelType = {
	orderbookId: string;
	orderId: string;
	creatorId: string;
	dominantToken: string;
	swapToken: string;
}