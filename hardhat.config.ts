import 'dotenv/config';
import '@nomicfoundation/hardhat-viem';
import '@nomicfoundation/hardhat-mocha';

export default {
  solidity: {
    version: '0.8.26',
  settings: { optimizer: { enabled: true, runs: 200 }, viaIR: true, evmVersion: process.env.EVM_VERSION || 'paris' }
  },
  paths: {
    tests: 'test-js'
  },
  networks: {
    hardhat: {
      type: 'edr-simulated',
      chain: { name: 'hardhat', id: 31337 }
    },
    // sepolia: { url: process.env.SEPOLIA_RPC_URL || '', accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [] },
  }
};
