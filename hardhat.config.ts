import 'dotenv/config';
import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox'; // includes ethers, chai, waffle, etc.
import 'solidity-coverage';
import 'hardhat-gas-reporter';
import 'hardhat-abi-exporter';
import 'hardhat-contract-sizer';

const { ALCHEMY_API_KEY, INFURA_API_KEY, PRIVATE_KEY, COINMARKETCAP_API_KEY } = process.env;

const rpc = (name: 'sepolia' | 'mainnet') =>
  `https://${name}.infura.io/v3/${INFURA_API_KEY ?? ''}`;

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.26',
    settings: { optimizer: { enabled: true, runs: 200 } }
  },
  networks: {
    hardhat: { chainId: 31337 },
    sepolia: {
      url: rpc('sepolia'),
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : []
    }
  },
  etherscan: { apiKey: process.env.ETHERSCAN_API_KEY || '' },
  gasReporter: {
    enabled: true,
    currency: 'USD',
    coinmarketcap: COINMARKETCAP_API_KEY || undefined
  },
  abiExporter: {
    path: './artifacts/abi',
    runOnCompile: true,
    clear: true,
    flat: true,
    spacing: 2
  },
  contractSizer: { runOnCompile: false, strict: true }
};

export default config;
