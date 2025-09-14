import { Wallet, TypedDataDomain, TypedDataField } from "ethers";
import { keccak256, toUtf8Bytes } from "ethers";

// Helper to sign RouteIntent typed data (EIP-712) using ethers v6
// Usage: node script/signRoute.ts (adapt as needed)

export type RouteIntent = {
  routeId: string; // bytes32 hex
  token: string;
  amount: string; // decimal string
  protocolFee: string;
  relayerFee: string;
  target: string;
  dstChainId: number;
  nonce: number;
  expiry: number;
  payloadHash: string; // bytes32
  recipient: string;
};

const RouteIntentTypes: Record<string, TypedDataField[]> = {
  RouteIntent: [
    { name: "routeId", type: "bytes32" },
    { name: "token", type: "address" },
    { name: "amount", type: "uint256" },
    { name: "protocolFee", type: "uint256" },
    { name: "relayerFee", type: "uint256" },
    { name: "target", type: "address" },
    { name: "dstChainId", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "expiry", type: "uint256" },
    { name: "payloadHash", type: "bytes32" },
    { name: "recipient", type: "address" }
  ]
};

export function signRoute(wallet: Wallet, domainName: string, domainVersion: string, chainId: number, verifyingContract: string, intent: RouteIntent): Promise<string> {
  const domain: TypedDataDomain = {
    name: domainName,
    version: domainVersion,
    chainId,
    verifyingContract
  };

  // ethers v6 exposes signTypedData on the Wallet instance
  // Use any-cast because of minor type differences between ethers versions
  // @ts-ignore
  return (wallet as any).signTypedData(domain, RouteIntentTypes, intent);
}

// Example standalone run (uncomment to test locally)
/*
(async () => {
  const w = Wallet.createRandom();
  const intent: RouteIntent = {
    routeId: keccak256(toUtf8Bytes("routePlanExample")),
    token: "0x0000000000000000000000000000000000000001",
    amount: "1000000000000000000",
    protocolFee: "1000000000000000",
    relayerFee: "0",
    target: "0x0000000000000000000000000000000000000002",
    dstChainId: 2,
    nonce: 1,
    expiry: Math.floor(Date.now() / 1000) + 3600,
    payloadHash: keccak256(toUtf8Bytes("payload")),
    recipient: w.address
  };
  const sig = await signRoute(w, "Zoopx Router", "1", 31337, "0x0000000000000000000000000000000000000003", intent);
  console.log(sig);
})();
*/
