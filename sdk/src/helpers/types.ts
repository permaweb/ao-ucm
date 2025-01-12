export type DependenciesType = {
	wallet: any,
	arweave?: any
}

export type OrderbookCreateType = {
	assetId: string;
}

export type OrderCreateType = {
	orderbookId: string;
	creatorId: string;
	dominantToken: string;
	swapToken: string;
	quantity: string;
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