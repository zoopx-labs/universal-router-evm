import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log('Deployer:', deployer.address);

  const feeRecipient = deployer.address;
  const defaultTarget = ethers.ZeroAddress; // set your adapter address later
  const SRC_CHAIN_ID = 1; // change per env

  const Router = await ethers.getContractFactory('Router');
  const router = await Router.deploy(feeRecipient, defaultTarget, SRC_CHAIN_ID);
  await router.waitForDeployment();

  console.log('Router deployed at:', await router.getAddress());
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
