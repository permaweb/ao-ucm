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
	baseToken: string; // Primary token in the pair
	quoteToken: string; // Secondary token in the pair
	baseTokenDenomination: string;
	quoteTokenDenomination: string;
	dominantToken: string; // Token being sent this order - determines order side (base token = Ask, quote token = Bid)
	swapToken: string; // Token being received this order
	quantity: string;
	action: 'Transfer' | 'Run-Action';
	unitPrice?: string;
	denomination?: string; // Denomination of the dominantToken (token being sent)
}

export type OrderCancelType = {
	creatorId?: string;
	walletAddress?: string;
	orderbookId: string;
	orderId: string;
	dominantToken: string;
	swapToken: string;
}