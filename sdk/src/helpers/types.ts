export type OrderCreateType = {
	orderbookId: string;
	profileId: string;
	dominantToken: string;
	swapToken: string;
	quantity: string;
	unitPrice?: string;
	denomination?: string;
}

export type OrderCancelType = {
	orderbookId: string;
	orderId: string;
	profileId: string;
	dominantToken: string;
	swapToken: string;
}