import type { ChainConfig } from './types';

// Export an array of chain configs. RPCs are read from environment variables; faucets are hints.
export const CHAINS: ChainConfig[] = [
  {
    name: 'ethereum-sepolia',
    chainId: 11155111,
    rpcEnv: 'RPC_SEPOLIA',
    explorer: 'https://sepolia.etherscan.io',
    faucetHint: 'https://sepoliafaucet.com/ or https://faucet.paradigm.xyz/'
  },
  {
    name: 'optimism-sepolia',
    chainId: 420,
    rpcEnv: 'RPC_OP_SEPOLIA',
    explorer: 'https://explorer.goerli.optimism.io',
    faucetHint: 'https://optimismfaucet.xyz/ or use a bridged test ETH'
  },
  {
    name: 'base-sepolia',
  chainId: 84532,
    rpcEnv: 'RPC_BASE_SEPOLIA',
    explorer: 'https://base-sepolia.blockscout.com',
    faucetHint: 'Base sepolia faucet (search official docs)'
  },
  {
    name: 'berachain-bepolia',
    chainId: 80069,
    rpcEnv: 'RPC_BERACHAIN_BEPOLIA',
    explorer: 'https://bartio.beratrail.io',
    faucetHint: 'Berachain bepolia faucet (search official docs)'
  },
  {
    name: 'qubetics-testnet',
    chainId: 9029,
    rpcEnv: 'RPC_QUBETICS_TESTNET',
    explorer: 'https://testnetv2.qubetics.work',
    faucetHint: 'Qubetics Testnet faucet (search official docs)'
  },
  {
    name: 'arbitrum-sepolia',
  chainId: 421614,
    rpcEnv: 'RPC_ARB_SEPOLIA',
    explorer: 'https://arbiscan.io',
    faucetHint: 'Arbitrum Sepolia faucet (see docs)'
  },
  {
    name: 'linea-sepolia',
  chainId: 59141,
    rpcEnv: 'RPC_LINEA_SEPOLIA',
    explorer: 'https://explorer.linea.build',
    faucetHint: 'Linea sepolia faucet (see docs)'
  },
  {
    name: 'bsc-testnet',
    chainId: 97,
    rpcEnv: 'RPC_BSC_TESTNET',
    explorer: 'https://testnet.bscscan.com',
    faucetHint: 'https://testnet.binance.org/faucet-smart'
  },
  {
    name: 'avalanche-fuji',
    chainId: 43113,
    rpcEnv: 'RPC_AVAX_FUJI',
    explorer: 'https://testnet.snowtrace.io',
    faucetHint: 'https://faucet.avax-test.network/'
  },
  {
    name: 'polygon-amoy',
    chainId: 80002,
    rpcEnv: 'RPC_POLYGON_AMOY',
    explorer: 'https://explorer.polygon.io',
    faucetHint: 'Polygon Amoy faucet (see polygon docs)'
  },
  {
    name: 'cronos-testnet',
    chainId: 338,
    rpcEnv: 'RPC_CRONOS_TESTNET',
    explorer: 'https://testnet-cronoscan.crypto.org',
    faucetHint: 'Cronos testnet faucet (see docs)'
  },
  {
    name: 'celo-alfajores',
    chainId: 44787,
    rpcEnv: 'RPC_CELO_ALFAJORES',
    explorer: 'https://alfajores.celoscan.io',
    faucetHint: 'https://celo.org/developers/faucet'
  },
  {
    name: 'bob-testnet',
    chainId: 97, // placeholder
    rpcEnv: 'RPC_BOB_TESTNET',
    explorer: 'https://bobscan.org',
    faucetHint: 'BOB testnet faucet (search docs)'
  },
  {
  name: 'world-testnet',
  chainId: 4801,
    rpcEnv: 'RPC_WORLD_TESTNET',
    explorer: '',
    faucetHint: 'World Chain testnet faucet (fill when available)'
  },
  {
    name: 'unichain-testnet',
    chainId: 1301,
    rpcEnv: 'RPC_UNICHAIN_TESTNET',
    explorer: '',
    faucetHint: 'Unichain faucet (fill when available)'
  },
  {
    name: 'xdc-apothem',
    chainId: 51, // placeholder
    rpcEnv: 'RPC_XDC_TESTNET',
    explorer: 'https://testnet.xdcscan.com/',
    faucetHint: 'XDC testnet faucet (fill when available)'
  },  
  {
    name: 'plume-testnet',
    chainId: 98867,
    rpcEnv: 'RPC_PLUME_TESTNET',
    explorer: 'https://testnet-explorer.plume.org',
    faucetHint: 'Plume faucet (see docs)'
  },
  {
    name: 'sei-evm-testnet',
    chainId: 1328, // placeholder
    rpcEnv: 'RPC_SEI_EVM_TESTNET',
    explorer: 'https://testnet.seitrace.com',
    faucetHint: 'Sei EVM testnet faucet (fill when available)'
  },
  {
    name: 'sonic-evm-testnet',
    chainId: 57054,
    rpcEnv: 'RPC_SONIC_EVM_TESTNET',
    explorer: 'https://blaze.soniclabs.com',
    faucetHint: 'Sonic EVM testnet faucet (fill when available)'
  }
];

export default CHAINS;
