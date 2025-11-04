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
	dominantToken: string; // Token being sent - determines order side (base token = Ask, quote token = Bid)
	swapToken: string; // Token being received
	quantity: string;
	action: 'Transfer' | 'Run-Action';
	unitPrice?: string;
	denomination?: string; // Denomination of the dominantToken (token being sent)
}

export type OrderCancelType = {
	orderbookId: string;
	orderId: string;
	creatorId: string;
	dominantToken: string;
	swapToken: string;
}