export type OrderCreateType = {
	orderbookId: string;
	profileId: string;
	dominantToken: string;
	swapToken: string;
	quantity: string;
	unitPrice?: string;
	denomination?: string;
}